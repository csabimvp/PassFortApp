#include <catch2/catch_test_macros.hpp>
#include "PFCrypto/PFBytes.hpp"
#include <cstdint>
#include <vector>

TEST_CASE("pf_echo round-trips bytes through an opaque handle", "[boundary]")
{
    const std::vector<uint8_t> input{1, 2, 3, 4, 5};
    auto r = pf::pf_echo(input.data(), input.size());

    REQUIRE(r.status == pf::Status::Ok);
    REQUIRE(r.handle != nullptr);
    REQUIRE(pf::pf_bytes_size(r.handle) == input.size());

    const uint8_t *out = pf::pf_bytes_data(r.handle);
    REQUIRE(std::vector<uint8_t>(out, out + input.size()) == input);

    pf::pf_bytes_free(r.handle);
}

TEST_CASE("pf_echo rejects null pointer with non-zero length", "[boundary]")
{
    auto r = pf::pf_echo(nullptr, 8);
    REQUIRE(r.status == pf::Status::BadInput);
    REQUIRE(r.handle == nullptr);
}
