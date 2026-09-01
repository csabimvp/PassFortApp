#include <catch2/catch_test_macros.hpp>

#include "Canonical.hpp"

TEST_CASE("canon put_u32 is big-endian", "[canon]") {
    pf::SecureBytes o;
    pf::canon::put_u32(o, 0x01020304);
    REQUIRE(o == pf::SecureBytes{0x01, 0x02, 0x03, 0x04});
}
