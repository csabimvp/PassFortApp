#include <catch2/catch_test_macros.hpp>

#include "botan_all.h" // minimized amalgamation -- no split botan/*.h headers

#include <cstdint>
#include <span>
#include <vector>

namespace {

// Full HKDF: extract-then-expand. derive_key(len, secret, salt, label) maps to
// RFC 5869 (IKM, salt, info) -- Botan runs HKDF-Extract(salt, IKM) -> PRK then
// HKDF-Expand(PRK, info, len) internally (see HKDF::perform_kdf).
std::string hkdf(size_t len, const std::vector<uint8_t> &ikm, const std::vector<uint8_t> &salt,
                 const std::vector<uint8_t> &info) {
    auto kdf = Botan::KDF::create_or_throw("HKDF(SHA-256)");
    const auto okm = kdf->derive_key(len, std::span{ikm}, std::span{salt}, std::span{info});
    return Botan::hex_encode(okm, /*uppercase=*/false);
}

// HKDF-Extract in isolation -> the 32-byte PRK. label must be empty.
std::string hkdf_prk(const std::vector<uint8_t> &ikm, const std::vector<uint8_t> &salt) {
    auto kdf = Botan::KDF::create_or_throw("HKDF-Extract(SHA-256)");
    const auto prk =
        kdf->derive_key(32, std::span{ikm}, std::span{salt}, std::span<const uint8_t>{});
    return Botan::hex_encode(prk, /*uppercase=*/false);
}

std::vector<uint8_t> bytes(std::string_view hex) { return Botan::hex_decode(hex); }

} // namespace

// RFC 5869 Appendix A.1 -- basic HKDF-SHA-256.
TEST_CASE("kat hkdf-sha256 matches RFC 5869 test case 1", "[kat][hkdf]") {
    const auto ikm = bytes("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b");
    const auto salt = bytes("000102030405060708090a0b0c");
    const auto info = bytes("f0f1f2f3f4f5f6f7f8f9");

    REQUIRE(hkdf_prk(ikm, salt) == "077709362c2e32df0ddc3f0dc47bba63"
                                   "90b6c73bb50f9c3122ec844ad7c2b3e5");
    REQUIRE(hkdf(42, ikm, salt, info) == "3cb25f25faacd57a90434f64d0362f2a"
                                         "2d2d0a90cf1a5a4c5db02d56ecc4c5bf"
                                         "34007208d5b887185865");
}

// RFC 5869 Appendix A.2 -- longer inputs and output (L = 82).
TEST_CASE("kat hkdf-sha256 matches RFC 5869 test case 2", "[kat][hkdf]") {
    const auto ikm = bytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
                           "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"
                           "404142434445464748494a4b4c4d4e4f");
    const auto salt = bytes("606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f"
                            "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"
                            "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf");
    const auto info = bytes("b0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecf"
                            "d0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeef"
                            "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff");

    REQUIRE(hkdf(82, ikm, salt, info) == "b11e398dc80327a1c8e7f78c596a4934"
                                         "4f012eda2d4efad8a050cc4c19afa97c"
                                         "59045a99cac7827271cb41c65e590e09"
                                         "da3275600c2f09b8367793a9aca3db71"
                                         "cc30c58179ec3e87c14c01d5c1f3434f"
                                         "1d87");
}

// RFC 5869 Appendix A.3 -- zero-length salt and info. This is the case that
// matters for the §5.1 key hierarchy: HKDF-Extract with an empty salt keys the
// HMAC with HashLen zero bytes, and the derivation still has to be exact.
TEST_CASE("kat hkdf-sha256 matches RFC 5869 test case 3 (empty salt/info)", "[kat][hkdf]") {
    const auto ikm = bytes("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b");
    const std::vector<uint8_t> empty;

    REQUIRE(hkdf_prk(ikm, empty) == "19ef24a32c717b167f33a91d6f648bdf"
                                    "96596776afdb6377ac434c1c293ccb04");
    REQUIRE(hkdf(42, ikm, empty, empty) == "8da4e775a563c18f715f802a063c5a31"
                                           "b8a11f5c5ee1879ec3454e5f3c738d2d"
                                           "9d201395faa4b61a96c8");
}

// Domain separation: same IKM, different info -> unrelated keys. This is the
// property the §5.1 hierarchy leans on ("pf-kek-v1" vs "pf-rec-v1" vs ...).
TEST_CASE("kat hkdf info string is a domain separator", "[kat][hkdf]") {
    const std::vector<uint8_t> ikm(32, 0x2a);
    const std::vector<uint8_t> salt(16, 0x00);
    const auto a = bytes("70662d6b656b2d7631"); // "pf-kek-v1"
    const auto b = bytes("70662d7265632d7631"); // "pf-rec-v1"

    REQUIRE(hkdf(32, ikm, salt, a) == hkdf(32, ikm, salt, a)); // deterministic
    REQUIRE(hkdf(32, ikm, salt, a) != hkdf(32, ikm, salt, b)); // separated
}
