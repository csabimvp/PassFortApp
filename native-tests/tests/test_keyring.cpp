#include <catch2/catch_test_macros.hpp>

#include "botan_all.h"
#include "keyring/hkdf.hpp"
#include "keyring/kdf.hpp"

#include <array>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

using pf::keyring::KdfParams;

namespace {

KdfParams params_with_salt(uint32_t m_kib, uint8_t salt_byte) {
    KdfParams p;
    p.kdf_id = 1;
    p.m_kib = m_kib;
    p.t = 3;
    p.p = 4;
    for (auto &b : p.salt)
        b = salt_byte;
    return p;
}

std::vector<uint8_t> pw_bytes(std::string_view s) { return {s.begin(), s.end()}; }

} // namespace

// -- argon2id_64 --------------------------------------------------------------

TEST_CASE("keyring argon2id_64 is 64 bytes and deterministic", "[keyring][kdf]") {
    const auto p = params_with_salt(64u * 1024, 0xAB);
    const auto pw = pw_bytes("correct horse battery staple");

    const auto a = pf::keyring::argon2id_64(pw.data(), pw.size(), p);
    const auto b = pf::keyring::argon2id_64(pw.data(), pw.size(), p);

    REQUIRE(a.size() == 64);
    REQUIRE(a == b);
}

TEST_CASE("keyring argon2id_64 depends on password and salt", "[keyring][kdf]") {
    const auto p1 = params_with_salt(64u * 1024, 0x01);
    const auto p2 = params_with_salt(64u * 1024, 0x02);
    const auto pw1 = pw_bytes("hunter2");
    const auto pw2 = pw_bytes("hunter3");

    const auto base = pf::keyring::argon2id_64(pw1.data(), pw1.size(), p1);
    REQUIRE(pf::keyring::argon2id_64(pw2.data(), pw2.size(), p1) != base); // password
    REQUIRE(pf::keyring::argon2id_64(pw1.data(), pw1.size(), p2) != base); // salt
}

// -- calibrate --------------------------------------------------------------

TEST_CASE("keyring calibrate returns pinned t/p and an in-range m", "[keyring][kdf]") {
    const auto p = pf::keyring::calibrate(/*target_ms=*/50);

    REQUIRE(p.kdf_id == 1);
    REQUIRE(p.t == 3);
    REQUIRE(p.p == 4);
    REQUIRE(p.m_kib >= 64u * 1024);
    REQUIRE(p.m_kib <= 4096u * 1024);

    bool salt_nonzero = false;
    for (auto b : p.salt)
        salt_nonzero |= (b != 0);
    REQUIRE(salt_nonzero); // filled from the OS CSPRNG
}

// -- the HKDF hierarchy --------------------------------------------------------

TEST_CASE("keyring derive_root expands argon64 into a deterministic 32B KEK", "[keyring][hkdf]") {
    const pf::SecureBytes argon64(64, 0x5A);

    const auto r1 = pf::keyring::derive_root(argon64);
    const auto r2 = pf::keyring::derive_root(argon64);

    REQUIRE(r1.kek.size() == 32);
    REQUIRE(r1.kek == r2.kek);
}

TEST_CASE("keyring derive_dek_subkeys yields four distinct 32B keys", "[keyring][hkdf]") {
    const pf::SecureBytes dek(32, 0x11);

    const auto s = pf::keyring::derive_dek_subkeys(dek);
    const std::array<const pf::SecureBytes *, 4> keys{&s.k_record, &s.k_index, &s.k_manifest,
                                                      &s.k_auth};

    for (size_t i = 0; i < keys.size(); ++i) {
        REQUIRE(keys[i]->size() == 32);
        for (size_t j = i + 1; j < keys.size(); ++j)
            REQUIRE(*keys[i] != *keys[j]); // domain-separated by info label
    }
}

TEST_CASE("keyring subkeys change with the input key material", "[keyring][hkdf]") {
    const pf::SecureBytes dek_a(32, 0x11);
    const pf::SecureBytes dek_b(32, 0x12);

    const auto a = pf::keyring::derive_dek_subkeys(dek_a);
    const auto b = pf::keyring::derive_dek_subkeys(dek_b);
    REQUIRE(a.k_record != b.k_record);
    REQUIRE(a.k_auth != b.k_auth);
}

// A frozen vector: if the HKDF label, hash, or empty-salt convention ever
// changes, this breaks -- which is the point, since all three are on-disk
// format (§5.1). Cross-checked against an independent HKDF-Expand(SHA-256):
//   PRK  = 0x5A x64
//   info = "pf-kek-v1"
//   T(1) = HMAC-SHA256(PRK, info , 0x01)  ->  the 32 bytes below
// A Swift or WASM port must reproduce this exactly.
TEST_CASE("keyring derive_root KEK is stable (format regression)", "[keyring][hkdf]") {
    const pf::SecureBytes argon64(64, 0x5A);
    const auto kek = pf::keyring::derive_root(argon64).kek;
    REQUIRE(Botan::hex_encode(kek, /*uppercase=*/false) ==
            "0e912dcef7615a65cff5ad95804ced476233180ecb60d942c86575f368accad7");
}

// The sync credential (ADR-0009). Not vault format, but the server holds
// SHA-256(k_auth) for every synced vault, so a change here locks every device
// out -- and the Swift / WASM hosts must agree byte for byte. The expected value
// was computed outside this codebase, with Python's standard library:
//   hmac.new(b"\x11" * 32, b"sync-auth" + b"\x01", hashlib.sha256).hexdigest()
// (HKDF-Expand to 32 bytes is that single HMAC block, RFC 5869 section 2.3.)
TEST_CASE("keyring k_auth is stable (sync credential regression)", "[keyring][hkdf][kat]") {
    const pf::SecureBytes dek(32, 0x11);
    const auto k_auth = pf::keyring::derive_dek_subkeys(dek).k_auth;
    REQUIRE(Botan::hex_encode(k_auth, /*uppercase=*/false) ==
            "46e9c595bdafdef1c21c3130ddd99fc965a44f40e551886cbb8ad7488ff056f9");
}

// The recovery-slot KEK (ADR-0007). Same on-disk-format contract as the vector
// above: HKDF-Expand(SHA-256), empty salt, info = "pf-rk-v1", input = the 32-byte
// recovery key (no Argon2). A Swift or WASM port must reproduce this exactly.
TEST_CASE("keyring derive_recovery_kek is stable (format regression)", "[keyring][hkdf]") {
    std::array<uint8_t, 32> rk{};
    rk.fill(0x2A);

    const auto rkek = pf::keyring::derive_recovery_kek(rk.data());
    REQUIRE(rkek.size() == 32);

    // Cross-check against an independent HKDF-Expand(SHA-256) call.
    auto kdf = Botan::KDF::create_or_throw("HKDF-Expand(SHA-256)");
    const std::string_view info = "pf-rk-v1";
    const auto expected = kdf->derive_key<pf::SecureBytes>(
        32, std::span<const uint8_t>(rk.data(), rk.size()), std::span<const uint8_t>{},
        std::span<const uint8_t>(reinterpret_cast<const uint8_t *>(info.data()), info.size()));
    REQUIRE(rkek == expected);

    REQUIRE(Botan::hex_encode(rkek, /*uppercase=*/false) ==
            "a160d1e46f010b2d8a0884a413de55b3f4488ae6410473c8ab21f1814dd754d1");

    // Domain separation: not the KEK label, not a DEK subkey.
    REQUIRE(rkek != pf::keyring::derive_root(pf::SecureBytes(rk.begin(), rk.end())).kek);
}
