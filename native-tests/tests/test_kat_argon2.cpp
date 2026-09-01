#include <catch2/catch_test_macros.hpp>

#include "botan_all.h" // minimized amalgamation -- no split botan/*.h headers

#include <cstdint>
#include <string>
#include <vector>

// RFC 9106 section 5.3 -- Argon2id test vector.
//
// The RFC vector uses the FULL Argon2 input set: password, salt, a secret key
// (K), and associated data (X). Botan's PasswordHash exposes all four through
// the 5-argument hash() overload (supports_associated_data / _keyed_operation
// are true for Argon2). KAT against the reduced set -- password+salt only --
// would compute a different digest and pass against the wrong number.
//
//   Memory: 32 KiB   Iterations: 3   Parallelism: 4   Tag length: 32
//   Password[32]: 01 x32
//   Salt[16]:     02 x16
//   Secret[8]:    03 x8
//   Assoc data[12]: 04 x12
TEST_CASE("kat argon2id matches RFC 9106 section 5.3", "[kat][argon2]") {
    const std::vector<uint8_t> password(32, 0x01);
    const std::vector<uint8_t> salt(16, 0x02);
    const std::vector<uint8_t> secret(8, 0x03);
    const std::vector<uint8_t> ad(12, 0x04);

    const auto expected = Botan::hex_decode(
        "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659");

    auto fam = Botan::PasswordHashFamily::create_or_throw("Argon2id");
    auto ph = fam->from_params(/*M=*/32, /*t=*/3, /*p=*/4); // M in KiB

    REQUIRE(ph->supports_associated_data());
    REQUIRE(ph->supports_keyed_operation());

    std::vector<uint8_t> out(expected.size());
    ph->hash(out, std::string(password.begin(), password.end()), salt, ad, secret);

    REQUIRE(Botan::hex_encode(out) == Botan::hex_encode(expected));
}
