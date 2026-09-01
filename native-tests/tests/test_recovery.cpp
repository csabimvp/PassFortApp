#include <catch2/catch_test_macros.hpp>

#include "PFCrypto/PFSession.hpp"
#include "botan_all.h"
#include "keyring/header.hpp"

#include <array>
#include <cstring>
#include <string>
#include <vector>

#if defined(__has_feature)
#if __has_feature(address_sanitizer)
#define PF_ASAN_BUILD 1
#endif
#endif
#if defined(__SANITIZE_ADDRESS__) && !defined(PF_ASAN_BUILD)
#define PF_ASAN_BUILD 1
#endif

// Recovery key: a second wrapped_dek slot in the header, keyed by 32 CSPRNG bytes
// via HKDF (no Argon2), wrapping the *same* DEK as the password slot. §5.6,
// ADR-0007.

namespace {

pf::keyring::KdfParams fast_kdf(uint8_t salt_byte = 0x44) {
    pf::keyring::KdfParams k;
    k.kdf_id = 1;
    k.m_kib = 8 * 1024;
    k.t = 1;
    k.p = 1;
    for (auto &b : k.salt)
        b = salt_byte;
    return k;
}

pf::KdfParams fast_pod_kdf() {
    pf::KdfParams p{};
    p.kdf_id = 1;
    p.m_kib = 8 * 1024;
    p.t = 1;
    p.p = 1;
    std::memset(p.salt, 0x55, sizeof p.salt);
    return p;
}

std::vector<uint8_t> bytes_of(std::string_view s) { return {s.begin(), s.end()}; }

std::vector<uint8_t> header_from(const pf::BytesResult &r) {
    return {pf::pf_bytes_data(r.handle), pf::pf_bytes_data(r.handle) + pf::pf_bytes_size(r.handle)};
}

} // namespace

// -- keyring level -----------------------------------------------------------

TEST_CASE("recovery: two-slot header round-trips on both password and key", "[recovery][header]") {
    const auto pw = bytes_of("correct horse");
    const std::array<uint8_t, 16> uuid{9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 6};
    const pf::SecureBytes dek(32, 0xC3);
    std::array<uint8_t, 32> rk{};
    rk.fill(0x2A);

    // Password header first, to get the password KEK.
    pf::keyring::RootKeys root;
    const auto pw_header =
        pf::keyring::header_encode(pw.data(), pw.size(), fast_kdf(), uuid, dek, root);
    REQUIRE(pw_header.size() == pf::keyring::kHeaderLen);

    const auto rec_header =
        pf::keyring::header_encode_with_recovery(fast_kdf(), uuid, dek, root.kek, rk.data());
    REQUIRE(rec_header.size() == pf::keyring::kHeaderLenWithRecovery);

    // Opens with the password (slot 0).
    pf::keyring::HeaderInfo info;
    pf::SecureBytes got;
    pf::keyring::RootKeys got_root;
    REQUIRE(pf::keyring::header_decode(rec_header.data(), rec_header.size(), pw.data(), pw.size(),
                                       info, got, got_root) == pf::Status::Ok);
    REQUIRE(got == dek);
    REQUIRE(info.slot_count == 2);

    // Opens with the recovery key (slot 1) -- same DEK.
    pf::SecureBytes got2;
    REQUIRE(pf::keyring::header_decode_recovery(rec_header.data(), rec_header.size(), rk.data(),
                                                info, got2) == pf::Status::Ok);
    REQUIRE(got2 == dek);
}

TEST_CASE("recovery: wrong key is AuthFailed, no oracle", "[recovery][header]") {
    const std::array<uint8_t, 16> uuid{};
    const pf::SecureBytes dek(32, 0x77);
    const pf::SecureBytes password_kek(32, 0x01);
    std::array<uint8_t, 32> rk{};
    rk.fill(0x2A);
    std::array<uint8_t, 32> wrong{};
    wrong.fill(0x2B);

    const auto header =
        pf::keyring::header_encode_with_recovery(fast_kdf(), uuid, dek, password_kek, rk.data());

    pf::keyring::HeaderInfo info;
    pf::SecureBytes got;
    REQUIRE(pf::keyring::header_decode_recovery(header.data(), header.size(), wrong.data(), info,
                                                got) == pf::Status::AuthFailed);
}

TEST_CASE("recovery: a password-only vault has no recovery slot -> NotFound",
          "[recovery][header]") {
    const auto pw = bytes_of("solo");
    const std::array<uint8_t, 16> uuid{};
    const pf::SecureBytes dek(32, 0x05);
    std::array<uint8_t, 32> rk{};
    rk.fill(0x2A);

    pf::keyring::RootKeys root;
    const auto header =
        pf::keyring::header_encode(pw.data(), pw.size(), fast_kdf(), uuid, dek, root);

    pf::keyring::HeaderInfo info;
    pf::SecureBytes got;
    REQUIRE(pf::keyring::header_decode_recovery(header.data(), header.size(), rk.data(), info,
                                                got) == pf::Status::NotFound);
}

TEST_CASE("recovery: stripping slot 1 fails the tag on slot 0", "[recovery][header]") {
    const auto pw = bytes_of("correct horse");
    const std::array<uint8_t, 16> uuid{};
    const pf::SecureBytes dek(32, 0x33);
    std::array<uint8_t, 32> rk{};
    rk.fill(0x2A);

    pf::keyring::RootKeys root;
    (void)pf::keyring::header_encode(pw.data(), pw.size(), fast_kdf(), uuid, dek, root);
    auto header =
        pf::keyring::header_encode_with_recovery(fast_kdf(), uuid, dek, root.kek, rk.data());

    // Forge a 1-slot header: keep the prefix + slot 0, drop slot 1, move
    // created_at up, and rewrite slot_count = 1. slot_count is in the AAD, so
    // slot 0's tag no longer verifies.
    constexpr size_t kPrefix = 53;
    constexpr size_t kSlot = 72;
    std::vector<uint8_t> forged(header.begin(), header.begin() + kPrefix + kSlot);
    forged.insert(forged.end(), header.end() - 8, header.end()); // created_at
    forged[52] = 1;                                              // slot_count 2 -> 1
    REQUIRE(forged.size() == pf::keyring::kHeaderLen);

    pf::keyring::HeaderInfo info;
    pf::SecureBytes got;
    pf::keyring::RootKeys got_root;
    REQUIRE(pf::keyring::header_decode(forged.data(), forged.size(), pw.data(), pw.size(), info,
                                       got, got_root) == pf::Status::AuthFailed);
}

// -- boundary level ---------------------------------------------------------

TEST_CASE("pf_recovery_wrap + pf_recovery_open: same vault, same records", "[recovery][session]") {
    const auto pw = bytes_of("open sesame");
    std::array<uint8_t, 32> rk{};
    Botan::system_rng().randomize(std::span<uint8_t>(rk.data(), rk.size()));

    const auto created = pf::pf_vault_create(pw.data(), pw.size(), fast_pod_kdf());
    REQUIRE(created.status == pf::Status::Ok);
    const auto header0 = header_from(created);
    pf::pf_bytes_free(created.handle);

    auto opened = pf::pf_session_open(header0.data(), header0.size(), pw.data(), pw.size());
    REQUIRE(opened.status == pf::Status::Ok);

    // Seal a record under the password session.
    const std::array<uint8_t, 16> id{1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4};
    const auto plaintext = bytes_of("top secret");
    const auto sealed_r =
        pf::pf_seal(opened.handle, id.data(), 1, 1, plaintext.data(), plaintext.size());
    REQUIRE(sealed_r.status == pf::Status::Ok);
    const std::vector<uint8_t> sealed(pf::pf_bytes_data(sealed_r.handle),
                                      pf::pf_bytes_data(sealed_r.handle) +
                                          pf::pf_bytes_size(sealed_r.handle));
    pf::pf_bytes_free(sealed_r.handle);

    // Add a recovery slot.
    const auto wrapped = pf::pf_recovery_wrap(opened.handle, rk.data());
    REQUIRE(wrapped.status == pf::Status::Ok);
    const auto header1 = header_from(wrapped);
    pf::pf_bytes_free(wrapped.handle);
    pf::pf_session_close(opened.handle);
    REQUIRE(header1.size() == pf::keyring::kHeaderLenWithRecovery);

    // The new header still opens with the password.
    auto pw_again = pf::pf_session_open(header1.data(), header1.size(), pw.data(), pw.size());
    REQUIRE(pw_again.status == pf::Status::Ok);
    pf::pf_session_close(pw_again.handle);

    // ...and opens with the recovery key, and reads the record sealed earlier.
    auto rec = pf::pf_recovery_open(header1.data(), header1.size(), rk.data());
    REQUIRE(rec.status == pf::Status::Ok);
    const auto out = pf::pf_open(rec.handle, id.data(), 1, 1, sealed.data(), sealed.size());
    REQUIRE(out.status == pf::Status::Ok);
    const std::vector<uint8_t> recovered(pf::pf_bytes_data(out.handle),
                                         pf::pf_bytes_data(out.handle) +
                                             pf::pf_bytes_size(out.handle));
    pf::pf_bytes_free(out.handle);
    REQUIRE(recovered == plaintext);
    pf::pf_session_close(rec.handle);
}

TEST_CASE("pf_recovery_open: wrong key AuthFailed, password-only vault NotFound",
          "[recovery][session]") {
    const auto pw = bytes_of("s3cret");
    std::array<uint8_t, 32> rk{};
    rk.fill(0x2A);
    std::array<uint8_t, 32> wrong{};
    wrong.fill(0x2C);

    const auto created = pf::pf_vault_create(pw.data(), pw.size(), fast_pod_kdf());
    REQUIRE(created.status == pf::Status::Ok);
    const auto header0 = header_from(created);
    pf::pf_bytes_free(created.handle);

    // No recovery slot yet.
    auto none = pf::pf_recovery_open(header0.data(), header0.size(), rk.data());
    REQUIRE(none.status == pf::Status::NotFound);
    REQUIRE(none.handle == nullptr);

    auto opened = pf::pf_session_open(header0.data(), header0.size(), pw.data(), pw.size());
    REQUIRE(opened.status == pf::Status::Ok);
    const auto wrapped = pf::pf_recovery_wrap(opened.handle, rk.data());
    REQUIRE(wrapped.status == pf::Status::Ok);
    const auto header1 = header_from(wrapped);
    pf::pf_bytes_free(wrapped.handle);
    pf::pf_session_close(opened.handle);

    auto bad = pf::pf_recovery_open(header1.data(), header1.size(), wrong.data());
    REQUIRE(bad.status == pf::Status::AuthFailed);
    REQUIRE(bad.handle == nullptr);
}

TEST_CASE("pf_recovery_wrap on a recovery-opened session is BadInput", "[recovery][session]") {
    const auto pw = bytes_of("first");
    std::array<uint8_t, 32> rk{};
    rk.fill(0x2A);

    const auto created = pf::pf_vault_create(pw.data(), pw.size(), fast_pod_kdf());
    REQUIRE(created.status == pf::Status::Ok);
    const auto header0 = header_from(created);
    pf::pf_bytes_free(created.handle);

    auto opened = pf::pf_session_open(header0.data(), header0.size(), pw.data(), pw.size());
    const auto wrapped = pf::pf_recovery_wrap(opened.handle, rk.data());
    const auto header1 = header_from(wrapped);
    pf::pf_bytes_free(wrapped.handle);
    pf::pf_session_close(opened.handle);

    auto rec = pf::pf_recovery_open(header1.data(), header1.size(), rk.data());
    REQUIRE(rec.status == pf::Status::Ok);

    // A recovery session holds no password KEK, so it cannot re-wrap slot 0.
    const auto again = pf::pf_recovery_wrap(rec.handle, rk.data());
    REQUIRE(again.status == pf::Status::BadInput);
    pf::pf_session_close(rec.handle);
}

TEST_CASE("recovery: null-pointer fuzz -> BadInput, never a crash", "[recovery][fuzz]") {
    std::array<uint8_t, 32> rk{};
    rk.fill(0x2A);
    std::vector<uint8_t> junk(pf::keyring::kHeaderLenWithRecovery, 0x00);

    REQUIRE(pf::pf_recovery_open(nullptr, 10, rk.data()).status == pf::Status::BadInput);
    REQUIRE(pf::pf_recovery_open(junk.data(), 0, rk.data()).status == pf::Status::BadInput);
    REQUIRE(pf::pf_recovery_open(junk.data(), junk.size(), nullptr).status == pf::Status::BadInput);
    // A well-formed-length but all-zero buffer: bad magic.
    REQUIRE(pf::pf_recovery_open(junk.data(), junk.size(), rk.data()).status ==
            pf::Status::BadInput);
    // pf_recovery_wrap's Session* is _Nonnull -- a literal nullptr won't compile,
    // so the s == nullptr guard is defensive-only (matches test_seam_fuzz.cpp).
}

#ifndef PF_ASAN_BUILD
// A deliberate use-after-free: the liveness sentinel is best-effort and only
// defined behaviour until the freed memory is reused (Session.hpp). Excluded from
// the ASan build, like the sibling case in test_seam_fuzz.cpp.
TEST_CASE("recovery: pf_recovery_wrap on a closed session returns Locked", "[recovery][fuzz]") {
    const auto pw = bytes_of("x");
    std::array<uint8_t, 32> rk{};
    rk.fill(0x2A);

    const auto created = pf::pf_vault_create(pw.data(), pw.size(), fast_pod_kdf());
    const auto header = header_from(created);
    pf::pf_bytes_free(created.handle);

    auto opened = pf::pf_session_open(header.data(), header.size(), pw.data(), pw.size());
    REQUIRE(opened.status == pf::Status::Ok);
    pf::Session *stale = opened.handle;
    pf::pf_session_close(opened.handle);

    REQUIRE(pf::pf_recovery_wrap(stale, rk.data()).status == pf::Status::Locked);
}
#endif // PF_ASAN_BUILD
