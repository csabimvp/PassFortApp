// internal/Secure.hpp
#pragma once
#include "botan_all.h" // minimized amalgamation -- no split botan/*.h headers
#include <cstdint>

// secure_vector keeps its pages out of swap only through Botan's locking_allocator module
// (ADR-0001, amended 2026-10-26). Without it the vector still scrubs on free but is never
// mlock()ed, which is how the build ran until 2026-10-26. A regenerated amalgamation that drops
// the module fails here instead of quietly losing the lock.
#if !defined(BOTAN_HAS_LOCKING_ALLOCATOR)
#error "Botan's locking_allocator module is missing; see scripts/build_botan.sh"
#endif

namespace pf {

using SecureBytes = Botan::secure_vector<uint8_t>;

// Botan::secure_vector already scrubs on destruction (secure_scrub_memory).
// This is here for buffers you must wipe *before* they go out of scope.
inline void scrub(SecureBytes &b) noexcept {
    if (!b.empty())
        Botan::secure_scrub_memory(b.data(), b.size());
}

} // namespace pf
