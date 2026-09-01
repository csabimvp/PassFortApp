#include <catch2/catch_test_macros.hpp>

#include "botan_all.h" // minimized amalgamation -- no split botan/*.h headers

#include <cstdint>
#include <string>
#include <vector>

namespace {

// One AEAD run. `dir` picks encrypt/decrypt; `buf` is transformed in place --
// on encrypt it comes back as ciphertext ‖ 16-byte tag, on decrypt `finish`
// verifies the tag and throws Botan::Invalid_Authentication_Tag on mismatch.
std::vector<uint8_t> aead(Botan::Cipher_Dir dir, const std::vector<uint8_t> &key,
                          const std::vector<uint8_t> &nonce, const std::vector<uint8_t> &ad,
                          const std::vector<uint8_t> &in) {
    auto mode = Botan::AEAD_Mode::create_or_throw("ChaCha20Poly1305", dir);
    mode->set_key(key);
    mode->set_associated_data(ad);
    mode->start(nonce);
    Botan::secure_vector<uint8_t> buf(in.begin(), in.end());
    mode->finish(buf);
    return {buf.begin(), buf.end()};
}

} // namespace

// RFC 8439 section 2.8.2 -- ChaCha20-Poly1305 AEAD test vector.
// Botan selects plain ChaCha20-Poly1305 for a 96-bit (12-byte) nonce; a 24-byte
// nonce selects XChaCha20-Poly1305 (HChaCha20 + ChaCha20-Poly1305). This vector
// exercises the 96-bit form, which is the primitive underneath both.
TEST_CASE("kat chacha20-poly1305 matches RFC 8439 section 2.8.2", "[kat][chacha]") {
    const auto key = Botan::hex_decode(
        "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f");
    // 32-bit "constant" 07000000 ‖ 64-bit IV 4041424344454647
    const auto nonce = Botan::hex_decode("070000004041424344454647");
    const auto aad = Botan::hex_decode("50515253c0c1c2c3c4c5c6c7");

    const std::string pt_str =
        "Ladies and Gentlemen of the class of '99: If I could offer you only one "
        "tip for the future, sunscreen would be it.";
    const std::vector<uint8_t> plaintext(pt_str.begin(), pt_str.end());

    // RFC 8439 section 2.8.2 output: ciphertext (114 B) followed by the 16-byte tag.
    const auto expected_ct_tag = Botan::hex_decode(
        "d31a8d34648e60db7b86afbc53ef7ec2"
        "a4aded51296e08fea9e2b5a736ee62d6"
        "3dbea45e8ca9671282fafb69da92728b"
        "1a71de0a9e060b2905d6a5b67ecd3b36"
        "92ddbd7f2d778b8c9803aee328091b58"
        "fab324e4fad675945585808b4831d7bc"
        "3ff4def08e4b7a9de576d26586cec64b"
        "6116"
        "1ae10b594f09e26a7e902ecbd0600691");

    const auto ct = aead(Botan::Cipher_Dir::Encryption, key, nonce, aad, plaintext);
    REQUIRE(Botan::hex_encode(ct) == Botan::hex_encode(expected_ct_tag));

    // Round-trips: decrypting the same bytes returns the exact plaintext.
    const auto back = aead(Botan::Cipher_Dir::Decryption, key, nonce, aad, ct);
    REQUIRE(Botan::hex_encode(back) == Botan::hex_encode(plaintext));
}

// XChaCha20-Poly1305 with a 24-byte nonce -- the form the vault format uses
// (§5.4). No published RFC vector; assert the round-trip, that a 192-bit nonce
// is accepted, and that a flipped ciphertext bit fails the tag check.
TEST_CASE("kat xchacha20-poly1305 24-byte nonce round-trips", "[kat][chacha]") {
    const std::vector<uint8_t> key(32, 0x11);
    const std::vector<uint8_t> nonce(24, 0x22);
    const std::vector<uint8_t> ad{0xaa, 0xbb, 0xcc};
    const std::string pt_str = "hunter2";
    const std::vector<uint8_t> plaintext(pt_str.begin(), pt_str.end());

    {
        auto probe = Botan::AEAD_Mode::create_or_throw("ChaCha20Poly1305",
                                                       Botan::Cipher_Dir::Encryption);
        REQUIRE(probe->valid_nonce_length(24));
        REQUIRE(probe->valid_nonce_length(12));
    }

    auto ct = aead(Botan::Cipher_Dir::Encryption, key, nonce, ad, plaintext);
    REQUIRE(ct.size() == plaintext.size() + 16); // 16-byte Poly1305 tag appended

    const auto back = aead(Botan::Cipher_Dir::Decryption, key, nonce, ad, ct);
    REQUIRE(Botan::hex_encode(back) == Botan::hex_encode(plaintext));

    ct[0] ^= 0x01;
    REQUIRE_THROWS_AS(aead(Botan::Cipher_Dir::Decryption, key, nonce, ad, ct),
                      Botan::Invalid_Authentication_Tag);
}
