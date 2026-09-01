#include <catch2/catch_test_macros.hpp>

#include "Canonical.hpp"
#include "PFCrypto/PFSession.hpp"
#include "keyring/header.hpp"

#include <array>
#include <cstring>
#include <string>
#include <vector>

// -- canonical encoders (Phase 2) -------------------------------------------

TEST_CASE("canon put_u32 is big-endian", "[canon]") {
    pf::SecureBytes o;
    pf::canon::put_u32(o, 0x01020304);
    REQUIRE(o == pf::SecureBytes{0x01, 0x02, 0x03, 0x04});
}

// -- the header codec (Phase 5, keyring level) -----------------------------

namespace {

// Deliberately cheap Argon2 so the suite stays fast; real vaults use calibrate().
pf::keyring::KdfParams fast_kdf(uint8_t salt_byte = 0x33) {
    pf::keyring::KdfParams k;
    k.kdf_id = 1;
    k.m_kib = 8 * 1024; // 8 MiB
    k.t = 1;
    k.p = 1;
    for (auto &b : k.salt)
        b = salt_byte;
    return k;
}

std::vector<uint8_t> bytes_of(std::string_view s) { return {s.begin(), s.end()}; }

} // namespace

TEST_CASE("header round-trips and rejects a wrong password", "[header]") {
    const auto pw = bytes_of("correct horse");
    const auto wrong = bytes_of("battery staple");
    const std::array<uint8_t, 16> uuid{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
    const pf::SecureBytes dek(32, 0xAA);

    pf::keyring::RootKeys root;
    const auto header =
        pf::keyring::header_encode(pw.data(), pw.size(), fast_kdf(), uuid, dek, root);
    REQUIRE(header.size() == pf::keyring::kHeaderLen);

    pf::keyring::HeaderInfo info;
    pf::SecureBytes got_dek;
    pf::keyring::RootKeys got_root;

    REQUIRE(pf::keyring::header_decode(header.data(), header.size(), pw.data(), pw.size(), info,
                                       got_dek, got_root) == pf::Status::Ok);
    REQUIRE(got_dek == dek);
    REQUIRE(info.vault_uuid == uuid);
    REQUIRE(info.kdf.m_kib == 8 * 1024);
    REQUIRE(info.format_version == 1);

    REQUIRE(pf::keyring::header_decode(header.data(), header.size(), wrong.data(), wrong.size(),
                                       info, got_dek, got_root) == pf::Status::AuthFailed);
}

TEST_CASE("header: any flipped byte fails AuthFailed, never a crash", "[header]") {
    const auto pw = bytes_of("hunter2");
    const std::array<uint8_t, 16> uuid{};
    const pf::SecureBytes dek(32, 0x01);

    pf::keyring::RootKeys root;
    auto header = pf::keyring::header_encode(pw.data(), pw.size(), fast_kdf(), uuid, dek, root);

    // Flip a byte in the AAD-covered region (a KDF-param byte) and in the tag.
    for (size_t offset : {20u, 60u, static_cast<unsigned>(header.size() - 12)}) {
        auto tampered = header;
        tampered[offset] ^= 0x40;

        pf::keyring::HeaderInfo info;
        pf::SecureBytes got_dek;
        pf::keyring::RootKeys got_root;
        const auto st = pf::keyring::header_decode(tampered.data(), tampered.size(), pw.data(),
                                                   pw.size(), info, got_dek, got_root);
        REQUIRE((st == pf::Status::AuthFailed || st == pf::Status::BadInput ||
                 st == pf::Status::Unsupported));
    }
}

TEST_CASE("header: a too-short buffer is BadInput, not a read past the end", "[header]") {
    const auto pw = bytes_of("x");
    std::array<uint8_t, 3> tiny{0x50, 0x46, 0x56};

    pf::keyring::HeaderInfo info;
    pf::SecureBytes got_dek;
    pf::keyring::RootKeys got_root;
    REQUIRE(pf::keyring::header_decode(tiny.data(), tiny.size(), pw.data(), pw.size(), info,
                                       got_dek, got_root) == pf::Status::BadInput);
    REQUIRE(pf::keyring::header_decode(nullptr, 0, pw.data(), pw.size(), info, got_dek, got_root) ==
            pf::Status::BadInput);
}

// -- the boundary facade (Phase 5, pf_* level) -----------------------------

namespace {

pf::KdfParams fast_pod_kdf() {
    pf::KdfParams p{};
    p.kdf_id = 1;
    p.m_kib = 8 * 1024;
    p.t = 1;
    p.p = 1;
    std::memset(p.salt, 0x77, sizeof p.salt);
    return p;
}

} // namespace

TEST_CASE("pf_vault_create + pf_session_open happy path", "[session]") {
    const auto pw = bytes_of("open sesame");

    const auto created = pf::pf_vault_create(pw.data(), pw.size(), fast_pod_kdf());
    REQUIRE(created.status == pf::Status::Ok);
    REQUIRE(created.handle != nullptr);

    const std::vector<uint8_t> header(pf::pf_bytes_data(created.handle),
                                      pf::pf_bytes_data(created.handle) +
                                          pf::pf_bytes_size(created.handle));
    pf::pf_bytes_free(created.handle);

    auto opened = pf::pf_session_open(header.data(), header.size(), pw.data(), pw.size());
    REQUIRE(opened.status == pf::Status::Ok);
    REQUIRE(opened.handle != nullptr);
    pf::pf_session_close(opened.handle);
}

TEST_CASE("pf_session_open: wrong password and tampered header both AuthFailed", "[session]") {
    const auto pw = bytes_of("s3cret");
    const auto wrong = bytes_of("s3cr3t");

    const auto created = pf::pf_vault_create(pw.data(), pw.size(), fast_pod_kdf());
    REQUIRE(created.status == pf::Status::Ok);
    std::vector<uint8_t> header(pf::pf_bytes_data(created.handle),
                                pf::pf_bytes_data(created.handle) +
                                    pf::pf_bytes_size(created.handle));
    pf::pf_bytes_free(created.handle);

    auto bad_pw = pf::pf_session_open(header.data(), header.size(), wrong.data(), wrong.size());
    REQUIRE(bad_pw.status == pf::Status::AuthFailed);
    REQUIRE(bad_pw.handle == nullptr);

    header[70] ^= 0x01; // inside the wrapped-DEK region
    auto tampered = pf::pf_session_open(header.data(), header.size(), pw.data(), pw.size());
    REQUIRE(tampered.status == pf::Status::AuthFailed);
    REQUIRE(tampered.handle == nullptr);
}

TEST_CASE("pf_session_open: 3-byte buffer is BadInput", "[session]") {
    const auto pw = bytes_of("x");
    std::array<uint8_t, 3> tiny{0x50, 0x46, 0x56};
    auto r = pf::pf_session_open(tiny.data(), tiny.size(), pw.data(), pw.size());
    REQUIRE(r.status == pf::Status::BadInput);
    REQUIRE(r.handle == nullptr);
}

TEST_CASE("pf_session_rewrap: new password opens, old does not, DEK is unchanged", "[session]") {
    const auto pw = bytes_of("first");
    const auto pw2 = bytes_of("second");

    const auto created = pf::pf_vault_create(pw.data(), pw.size(), fast_pod_kdf());
    REQUIRE(created.status == pf::Status::Ok);
    const std::vector<uint8_t> header0(pf::pf_bytes_data(created.handle),
                                       pf::pf_bytes_data(created.handle) +
                                           pf::pf_bytes_size(created.handle));
    pf::pf_bytes_free(created.handle);

    auto session = pf::pf_session_open(header0.data(), header0.size(), pw.data(), pw.size());
    REQUIRE(session.status == pf::Status::Ok);

    const auto rewrapped = pf::pf_session_rewrap(session.handle, pw2.data(), pw2.size());
    REQUIRE(rewrapped.status == pf::Status::Ok);
    const std::vector<uint8_t> header1(pf::pf_bytes_data(rewrapped.handle),
                                       pf::pf_bytes_data(rewrapped.handle) +
                                           pf::pf_bytes_size(rewrapped.handle));
    pf::pf_bytes_free(rewrapped.handle);
    pf::pf_session_close(session.handle);

    REQUIRE(header1 != header0);

    // The new header opens with pw2 and not with pw1.
    auto old_pw = pf::pf_session_open(header1.data(), header1.size(), pw.data(), pw.size());
    REQUIRE(old_pw.status == pf::Status::AuthFailed);
    auto new_pw = pf::pf_session_open(header1.data(), header1.size(), pw2.data(), pw2.size());
    REQUIRE(new_pw.status == pf::Status::Ok);
    pf::pf_session_close(new_pw.handle);

    // Same DEK under both headers -- decode each at the keyring level and compare.
    pf::keyring::HeaderInfo i0;
    pf::keyring::HeaderInfo i1;
    pf::SecureBytes dek0;
    pf::SecureBytes dek1;
    pf::keyring::RootKeys r0;
    pf::keyring::RootKeys r1;
    REQUIRE(pf::keyring::header_decode(header0.data(), header0.size(), pw.data(), pw.size(), i0,
                                       dek0, r0) == pf::Status::Ok);
    REQUIRE(pf::keyring::header_decode(header1.data(), header1.size(), pw2.data(), pw2.size(), i1,
                                       dek1, r1) == pf::Status::Ok);
    REQUIRE(dek0 == dek1);
    REQUIRE(i0.vault_uuid == i1.vault_uuid);
}

TEST_CASE("pf_session_close is a no-op on nil", "[session]") {
    pf::pf_session_close(nullptr); // must not crash
    SUCCEED();
    // Exhaustive null / closed-handle fuzzing of the whole surface is Phase 8
    // (test_seam_fuzz.cpp); the _Nonnull annotations block literal nullptr here.
}
