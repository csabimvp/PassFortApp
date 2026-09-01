#include <catch2/catch_test_macros.hpp>

#include "PFCrypto/PFManifest.hpp"
#include "PFCrypto/PFSession.hpp"
#include "support/test_vault.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

using namespace pf_test;

#if defined(__has_feature)
#if __has_feature(address_sanitizer)
#define PF_ASAN_BUILD 1
#endif
#endif
#if defined(__SANITIZE_ADDRESS__) && !defined(PF_ASAN_BUILD)
#define PF_ASAN_BUILD 1
#endif

namespace {
constexpr size_t kHuge = std::numeric_limits<size_t>::max();
} // namespace

// §13.1: every boundary function with null pointers, zero/huge lengths, closed
// handles, double frees -> a Status, never a trap.

TEST_CASE("seam fuzz: null pointer with non-zero length -> BadInput", "[fuzz]") {
    const std::vector<uint8_t> pw{'p', 'w'};
    const auto header = make_header(pw);
    Vault v;
    const std::array<uint8_t, 16> id{1};

    REQUIRE(drain(pf::pf_echo(nullptr, 8)) == pf::Status::BadInput);
    REQUIRE(drain(pf::pf_vault_create(nullptr, 8, fast_kdf())) == pf::Status::BadInput);
    REQUIRE(pf::pf_session_open(nullptr, 8, pw.data(), pw.size()).status == pf::Status::BadInput);
    REQUIRE(pf::pf_session_open(header.data(), header.size(), nullptr, 8).status ==
            pf::Status::BadInput);
    REQUIRE(drain(pf::pf_seal(v.session, id.data(), 1, 1, nullptr, 8)) == pf::Status::BadInput);
    REQUIRE(drain(pf::pf_open(v.session, id.data(), 1, 1, nullptr, 8)) == pf::Status::BadInput);

    auto mac = pf::pf_mac_init(v.session, 1);
    REQUIRE(mac.status == pf::Status::Ok);
    REQUIRE(pf::pf_mac_update(mac.handle, id.data(), 1, nullptr, 8) == pf::Status::BadInput);
    pf::pf_mac_free(mac.handle);
}

TEST_CASE("seam fuzz: zero length is handled per contract, never a crash", "[fuzz]") {
    Vault v;
    const std::array<uint8_t, 16> id{2};
    std::array<uint8_t, 1> buf{};

    // Valid empty input:
    REQUIRE(drain(pf::pf_echo(buf.data(), 0)) == pf::Status::Ok);
    REQUIRE(drain(pf::pf_seal(v.session, id.data(), 1, 1, buf.data(), 0)) == pf::Status::Ok);
    auto empty_pw = pf::pf_vault_create(buf.data(), 0, fast_kdf());
    REQUIRE(empty_pw.status == pf::Status::Ok); // password policy is a UI concern, not the seam's
    pf::pf_bytes_free(empty_pw.handle);

    // Too short:
    REQUIRE(drain(pf::pf_open(v.session, id.data(), 1, 1, buf.data(), 0)) == pf::Status::BadInput);
    REQUIRE(pf::pf_session_open(buf.data(), 0, buf.data(), 1).status == pf::Status::BadInput);
}

TEST_CASE("seam fuzz: absurd length -> BadInput, no over-read or huge alloc", "[fuzz]") {
    const std::vector<uint8_t> pw{'p', 'w'};
    const auto header = make_header(pw);
    Vault v;
    const std::array<uint8_t, 16> id{3};
    std::array<uint8_t, 1> buf{};

    REQUIRE(drain(pf::pf_echo(buf.data(), kHuge)) == pf::Status::BadInput);
    REQUIRE(drain(pf::pf_vault_create(buf.data(), kHuge, fast_kdf())) == pf::Status::BadInput);
    REQUIRE(pf::pf_session_open(header.data(), kHuge, pw.data(), pw.size()).status ==
            pf::Status::BadInput);
    REQUIRE(pf::pf_session_open(header.data(), header.size(), buf.data(), kHuge).status ==
            pf::Status::BadInput);
    REQUIRE(drain(pf::pf_seal(v.session, id.data(), 1, 1, buf.data(), kHuge)) ==
            pf::Status::BadInput);
    REQUIRE(drain(pf::pf_open(v.session, id.data(), 1, 1, buf.data(), kHuge)) ==
            pf::Status::BadInput);

    auto mac = pf::pf_mac_init(v.session, 1);
    REQUIRE(pf::pf_mac_update(mac.handle, id.data(), 1, buf.data(), kHuge) == pf::Status::BadInput);
    pf::pf_mac_free(mac.handle);
}

TEST_CASE("seam fuzz: freeing nil is a no-op", "[fuzz]") {
    pf::pf_bytes_free(nullptr);
    pf::pf_session_close(nullptr);
    pf::pf_mac_free(nullptr);
    SUCCEED();
    // Passing a Bytes* to the wrong free, or double-freeing, is caller error the
    // C ABI cannot catch (§13 note). The liveness sentinel below is the only
    // mitigation, and it is best-effort.
}

#ifndef PF_ASAN_BUILD
// These exercise a handle after it is freed. The liveness sentinel makes that
// return an error instead of using freed key material -- but the check itself
// reads the freed allocation, which is UB once the memory is reused. Excluded
// from the ASan build, where that read is (correctly) flagged.

TEST_CASE("seam fuzz: a call on a freed Mac handle returns BadInput", "[fuzz]") {
    Vault v;
    auto mac = pf::pf_mac_init(v.session, 1);
    REQUIRE(mac.status == pf::Status::Ok);
    pf::Mac *stale = mac.handle;
    pf::pf_mac_free(mac.handle);

    const std::array<uint8_t, 16> id{4};
    std::array<uint8_t, 48> sealed{};
    REQUIRE(pf::pf_mac_update(stale, id.data(), 1, sealed.data(), sealed.size()) ==
            pf::Status::BadInput);
    REQUIRE(pf::pf_mac_finish(stale).status == pf::Status::BadInput);
}

TEST_CASE("seam fuzz: a call on a closed session returns Locked", "[fuzz]") {
    const std::vector<uint8_t> pw{'p', 'w'};
    const auto header = make_header(pw);
    auto opened = pf::pf_session_open(header.data(), header.size(), pw.data(), pw.size());
    REQUIRE(opened.status == pf::Status::Ok);
    pf::Session *stale = opened.handle;
    pf::pf_session_close(opened.handle);

    const std::array<uint8_t, 16> id{5};
    std::array<uint8_t, 8> pt{};
    std::array<uint8_t, 48> sealed{};

    REQUIRE(drain(pf::pf_seal(stale, id.data(), 1, 1, pt.data(), pt.size())) == pf::Status::Locked);
    REQUIRE(drain(pf::pf_open(stale, id.data(), 1, 1, sealed.data(), sealed.size())) ==
            pf::Status::Locked);
    REQUIRE(pf::pf_mac_init(stale, 1).status == pf::Status::Locked);
    REQUIRE(drain(pf::pf_session_rewrap(stale, pw.data(), pw.size())) == pf::Status::Locked);
}
#endif // PF_ASAN_BUILD
