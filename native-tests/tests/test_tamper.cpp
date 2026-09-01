#include <catch2/catch_test_macros.hpp>

#include "PFCrypto/PFSession.hpp"
#include "support/test_vault.hpp"

#include <array>
#include <vector>

using namespace pf_test;

// §13.1: flip one bit in nonce / ciphertext / tag / AAD input / header and
// assert AuthFailed -- not a crash, not success, not a different code.

TEST_CASE("tamper: flipping any bit of a sealed record yields AuthFailed", "[tamper]") {
    Vault v;
    const std::array<uint8_t, 16> id{7, 7, 7, 1};
    const std::vector<uint8_t> pt{'p', 'a', 'y', 'l', 'o', 'a', 'd', '!'};
    const auto sealed = bytes_of(pf::pf_seal(v.session, id.data(), 3, 2, pt.data(), pt.size()));

    for (size_t byte = 0; byte < sealed.size(); ++byte) {
        for (int bit = 0; bit < 8; ++bit) {
            auto bad = sealed;
            bad[byte] ^= static_cast<uint8_t>(1u << bit);
            const auto r = pf::pf_open(v.session, id.data(), 3, 2, bad.data(), bad.size());
            REQUIRE(r.status == pf::Status::AuthFailed);
            REQUIRE(r.handle == nullptr);
        }
    }
}

TEST_CASE("tamper: flipping any AAD component yields AuthFailed", "[tamper]") {
    Vault v;
    const std::array<uint8_t, 16> id{1, 2, 3, 4, 5};
    std::array<uint8_t, 16> id_flipped = id;
    id_flipped[0] ^= 0x01;

    const std::vector<uint8_t> pt{'x'};
    const auto sealed = bytes_of(pf::pf_seal(v.session, id.data(), 10, 4, pt.data(), pt.size()));

    REQUIRE(drain(pf::pf_open(v.session, id_flipped.data(), 10, 4, sealed.data(), sealed.size())) ==
            pf::Status::AuthFailed); // record_uuid
    REQUIRE(drain(pf::pf_open(v.session, id.data(), 11, 4, sealed.data(), sealed.size())) ==
            pf::Status::AuthFailed); // version
    REQUIRE(drain(pf::pf_open(v.session, id.data(), 10, 5, sealed.data(), sealed.size())) ==
            pf::Status::AuthFailed); // schema
    REQUIRE(drain(pf::pf_open(v.session, id.data(), 10, 4, sealed.data(), sealed.size())) ==
            pf::Status::Ok); // untouched -> still opens
}

TEST_CASE("tamper: flipping any header byte before created_at breaks the open", "[tamper]") {
    const std::vector<uint8_t> pw{'m', 'a', 's', 't', 'e', 'r'};
    const auto header = make_header(pw, fast_kdf(/*m_kib=*/16)); // ~130 opens, keep it fast

    {
        auto ok = pf::pf_session_open(header.data(), header.size(), pw.data(), pw.size());
        REQUIRE(ok.status == pf::Status::Ok);
        pf::pf_session_close(ok.handle);
    }

    auto open_bad = [&](const std::vector<uint8_t> &h) {
        auto r = pf::pf_session_open(h.data(), h.size(), pw.data(), pw.size());
        if (r.handle != nullptr)
            pf::pf_session_close(r.handle);
        return r.status;
    };

    // §5.3 layout: kdf_m_kib/t/p occupy bytes [23, 35). Flipping a high bit there
    // just makes Argon2 huge, so those fields get explicit cases below rather
    // than a bitwise sweep; the trailing 8-byte created_at is not AAD-covered.
    constexpr size_t kKdfIntsBegin = 23;
    constexpr size_t kKdfIntsEnd = 35;
    const size_t kCreatedAt = header.size() - 8; // slot_count-dependent header length (ADR-0007)

    for (size_t byte = 0; byte < header.size(); ++byte) {
        if (byte >= kKdfIntsBegin && byte < kKdfIntsEnd)
            continue;
        auto bad = header;
        bad[byte] ^= 0x01;
        const auto st = open_bad(bad);
        if (byte < kCreatedAt)
            REQUIRE(st != pf::Status::Ok); // AuthFailed / BadInput / Unsupported
        else
            REQUIRE(st == pf::Status::Ok); // created_at is unauthenticated by design
    }

    // The KDF integer fields, explicitly:
    for (size_t field_off : {kKdfIntsBegin, kKdfIntsBegin + 4, kKdfIntsBegin + 8}) {
        auto huge = header;
        for (size_t i = 0; i < 4; ++i)
            huge[field_off + i] = 0xFF; // absurd cost -> rejected before Argon2 runs
        REQUIRE(open_bad(huge) == pf::Status::AuthFailed);

        auto nudged = header;
        nudged[field_off + 3] ^= 0x02; // still-sane but wrong -> AAD tag catches it
        REQUIRE(open_bad(nudged) == pf::Status::AuthFailed);
    }
}
