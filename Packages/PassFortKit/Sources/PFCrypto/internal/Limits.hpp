// internal/Limits.hpp -- shared seam guards. NOT exported.
#pragma once

#include <cstddef>

namespace pf {

// Upper bound on any single (pointer, length) input across the seam. A
// caller-supplied length cannot be validated against the real buffer size, so
// above this the boundary returns BadInput without reading or allocating --
// SIZE_MAX and other absurd values fail fast instead of over-reading or trying a
// multi-exabyte allocation (§13.1 seam-fuzz). Well above any real password,
// header, or record payload.
inline constexpr std::size_t kMaxSeamInput = 256u * 1024 * 1024; // 256 MiB

} // namespace pf
