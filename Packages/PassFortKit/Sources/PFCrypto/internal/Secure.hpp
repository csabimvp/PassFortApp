// internal/Secure.hpp
#pragma once
#include "botan_all.h" // minimized amalgamation -- no split botan/*.h headers
#include <cstdint>

namespace pf {

using SecureBytes = Botan::secure_vector<uint8_t>;

// Botan::secure_vector already scrubs on destruction (secure_scrub_memory).
// This is here for buffers you must wipe *before* they go out of scope.
inline void scrub(SecureBytes &b) noexcept {
    if (!b.empty())
        Botan::secure_scrub_memory(b.data(), b.size());
}

} // namespace pf
