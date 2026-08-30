#pragma once
#include <cstdint>

namespace pf {

// Plain enum, fixed width -- crosses the seam as an int32. Translated to a Swift
// error by PassFortCrypto. A wrong password and a corrupt record BOTH map to
// AuthFailed so the API is not a decryption oracle (architecture §13, ADR-0002).
enum class Status : int32_t {
    Ok = 0,
    BadInput = 1,
    Locked = 2,
    AuthFailed = 3,
    NotFound = 4,
    Unsupported = 5,
    Internal = 99
};

} // namespace pf
