#include <catch2/catch_test_macros.hpp>

#include "PFCrypto/PFSession.hpp"

#include <array>
#include <cstring>
#include <vector>

namespace {

pf::KdfParams fast_kdf() {
    pf::KdfParams p{};
    p.kdf_id = 1;
    p.m_kib = 8 * 1024; // 8 MiB -- cheap, this suite is not KAT'ing Argon2
    p.t = 1;
    p.p = 1;
    std::memset(p.salt, 0x5c, sizeof p.salt);
    return p;
}

// Owns one live session for a test body.
struct TestVault {
    pf::Session *session = nullptr;

    TestVault() {
        const std::vector<uint8_t> pw{'p', 'w'};
        auto created = pf::pf_vault_create(pw.data(), pw.size(), fast_kdf());
        REQUIRE(created.status == pf::Status::Ok);
        const std::vector<uint8_t> header(pf::pf_bytes_data(created.handle),
                                          pf::pf_bytes_data(created.handle) +
                                              pf::pf_bytes_size(created.handle));
        pf::pf_bytes_free(created.handle);

        auto opened = pf::pf_session_open(header.data(), header.size(), pw.data(), pw.size());
        REQUIRE(opened.status == pf::Status::Ok);
        session = opened.handle;
    }
    ~TestVault() { pf::pf_session_close(session); }
};

std::vector<uint8_t> take(pf::BytesResult r) {
    REQUIRE(r.status == pf::Status::Ok);
    std::vector<uint8_t> out(pf::pf_bytes_data(r.handle),
                             pf::pf_bytes_data(r.handle) + pf::pf_bytes_size(r.handle));
    pf::pf_bytes_free(r.handle);
    return out;
}

// Status of a call, freeing any handle it returned.
pf::Status status_of(pf::BytesResult r) {
    if (r.handle != nullptr)
        pf::pf_bytes_free(r.handle);
    return r.status;
}

constexpr size_t kOverhead = 24 + 16; // nonce + Poly1305 tag

} // namespace

TEST_CASE("seal then open returns the exact plaintext", "[seal]") {
    TestVault v;
    const std::array<uint8_t, 16> id{9, 9, 9, 1, 2, 3};
    const std::vector<uint8_t> pt{'h', 'u', 'n', 't', 'e', 'r', '2'};

    const auto sealed = take(pf::pf_seal(v.session, id.data(), 1, 1, pt.data(), pt.size()));
    REQUIRE(sealed.size() == pt.size() + kOverhead);

    REQUIRE(take(pf::pf_open(v.session, id.data(), 1, 1, sealed.data(), sealed.size())) == pt);
}

TEST_CASE("open with the wrong identity fails AuthFailed (§5.4 AAD binding)", "[seal]") {
    TestVault v;
    const std::array<uint8_t, 16> id{1, 2, 3, 4};
    const std::array<uint8_t, 16> other{4, 3, 2, 1};
    const std::vector<uint8_t> pt{'x', 'y', 'z'};

    const auto sealed = take(pf::pf_seal(v.session, id.data(), 7, 2, pt.data(), pt.size()));

    REQUIRE(status_of(pf::pf_open(v.session, other.data(), 7, 2, sealed.data(), sealed.size())) ==
            pf::Status::AuthFailed); // wrong record_uuid
    REQUIRE(status_of(pf::pf_open(v.session, id.data(), 8, 2, sealed.data(), sealed.size())) ==
            pf::Status::AuthFailed); // wrong version
    REQUIRE(status_of(pf::pf_open(v.session, id.data(), 7, 3, sealed.data(), sealed.size())) ==
            pf::Status::AuthFailed); // wrong schema
    REQUIRE(status_of(pf::pf_open(v.session, id.data(), 7, 2, sealed.data(), sealed.size())) ==
            pf::Status::Ok); // correct -> still opens
}

TEST_CASE("seal/open handles empty plaintext", "[seal]") {
    TestVault v;
    const std::array<uint8_t, 16> id{5};
    const std::array<uint8_t, 1> pt{}; // non-null pointer, length 0

    const auto sealed = take(pf::pf_seal(v.session, id.data(), 1, 1, pt.data(), 0));
    REQUIRE(sealed.size() == kOverhead);
    REQUIRE(take(pf::pf_open(v.session, id.data(), 1, 1, sealed.data(), sealed.size())).empty());
}

TEST_CASE("seal/open round-trips 1 MiB", "[seal]") {
    TestVault v;
    const std::array<uint8_t, 16> id{6};
    std::vector<uint8_t> pt(1024 * 1024);
    for (size_t i = 0; i < pt.size(); ++i)
        pt[i] = static_cast<uint8_t>(i * 31 + 7);

    const auto sealed = take(pf::pf_seal(v.session, id.data(), 1, 1, pt.data(), pt.size()));
    REQUIRE(sealed.size() == pt.size() + kOverhead);
    REQUIRE(take(pf::pf_open(v.session, id.data(), 1, 1, sealed.data(), sealed.size())) == pt);
}

TEST_CASE("open rejects a truncated sealed blob with BadInput", "[seal]") {
    TestVault v;
    const std::array<uint8_t, 16> id{2};
    std::array<uint8_t, 20> too_short{}; // < nonce(24) + tag(16)

    REQUIRE(status_of(pf::pf_open(v.session, id.data(), 1, 1, too_short.data(),
                                  too_short.size())) == pf::Status::BadInput);
}

TEST_CASE("open on any flipped sealed byte fails AuthFailed", "[seal]") {
    TestVault v;
    const std::array<uint8_t, 16> id{3};
    const std::vector<uint8_t> pt{'a', 'b', 'c', 'd'};
    const auto sealed = take(pf::pf_seal(v.session, id.data(), 1, 1, pt.data(), pt.size()));

    for (size_t i : {size_t{0}, size_t{24}, sealed.size() - 1}) { // nonce, ciphertext, tag
        auto bad = sealed;
        bad[i] ^= 0x80;
        REQUIRE(status_of(pf::pf_open(v.session, id.data(), 1, 1, bad.data(), bad.size())) ==
                pf::Status::AuthFailed);
    }
}

TEST_CASE("a record sealed under one vault will not open under another", "[seal]") {
    TestVault a;
    TestVault b;
    const std::array<uint8_t, 16> id{4};
    const std::vector<uint8_t> pt{'s', 'e', 'c', 'r', 'e', 't'};

    const auto sealed = take(pf::pf_seal(a.session, id.data(), 1, 1, pt.data(), pt.size()));
    // Different DEK -> different k_record, and the AAD carries a's vault_uuid.
    REQUIRE(status_of(pf::pf_open(b.session, id.data(), 1, 1, sealed.data(), sealed.size())) ==
            pf::Status::AuthFailed);
}
