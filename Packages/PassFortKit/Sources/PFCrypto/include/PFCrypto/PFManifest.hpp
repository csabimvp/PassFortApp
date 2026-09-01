// include/PFCrypto/PFManifest.hpp -- PUBLIC. The streaming anti-rollback MAC
// (§5.5). k_manifest never leaves C++, so Swift drives this row by row: it
// decides the (UUID-sorted) iteration order, C++ does the hashing.
#pragma once

#include "PFBytes.hpp" // BytesResult
#include "PFStatus.hpp"

#include <cstddef>
#include <cstdint>

#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-extension"
#pragma clang diagnostic ignored "-Wnullability-completeness"
#define PF_NULLABLE _Nullable
#define PF_NONNULL _Nonnull
#else
#define PF_NULLABLE
#define PF_NONNULL
#endif

namespace pf {

struct Session; // from PFSession.hpp
struct Mac;     // opaque -- the in-progress manifest-MAC state

struct MacResult {
    Mac *PF_NULLABLE handle; // nil on failure
    Status status;
};

// Seed HMAC-SHA-256 with the session's k_manifest and fold in vault_version
// (§5.5). A stale session handle returns Locked.
MacResult pf_mac_init(Session *PF_NONNULL s, uint64_t vault_version) noexcept;

// Fold one record: SHA-256(sealed) internally, then
// uuid , version(u64 BE) , that hash into the running HMAC. Call once per
// record, in UUID-sorted order. After pf_mac_finish -> Status::BadInput.
Status pf_mac_update(Mac *PF_NONNULL m, const uint8_t *record_uuid, uint64_t version,
                     const uint8_t *sealed, size_t sealed_len) noexcept;

// Finalize -> the 32-byte manifest MAC. Single-shot: a second call returns
// {nil, BadInput}.
BytesResult pf_mac_finish(Mac *PF_NONNULL m) noexcept;

// Release the handle. Mandatory (opaque owned memory, §6.1 rule 7). Safe on nil.
void pf_mac_free(Mac *PF_NULLABLE m) noexcept;

} // namespace pf

#undef PF_NULLABLE
#undef PF_NONNULL
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
