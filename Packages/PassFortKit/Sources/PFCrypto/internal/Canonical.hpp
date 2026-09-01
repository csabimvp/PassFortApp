// internal/Canonical.hpp
#pragma once
#include "Secure.hpp"
#include <cstdint>
#include <cstring>

namespace pf::canon {

// All multi-byte integers in the vault format are BIG-ENDIAN. Pick one and never
// think about it again. (Botan's own serializers are big-endian too — no conflict.)
inline void put_u8(SecureBytes &o, uint8_t v) { o.push_back(v); }
inline void put_u16(SecureBytes &o, uint16_t v) {
    o.push_back(v >> 8);
    o.push_back(v & 0xFF);
}
inline void put_u32(SecureBytes &o, uint32_t v) {
    for (int s = 24; s >= 0; s -= 8)
        o.push_back((v >> s) & 0xFF);
}
inline void put_u64(SecureBytes &o, uint64_t v) {
    for (int s = 56; s >= 0; s -= 8)
        o.push_back((v >> s) & 0xFF);
}
inline void put_bytes(SecureBytes &o, const uint8_t *p, size_t n) { o.insert(o.end(), p, p + n); }

// A matching reader with bounds checks lives in header.cpp — it must return
// Status::BadInput on a short buffer, never read past the end.

} // namespace pf::canon
