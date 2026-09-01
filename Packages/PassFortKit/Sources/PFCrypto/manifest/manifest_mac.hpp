// manifest/manifest_mac.hpp -- the streaming anti-rollback MAC (§5.5). Internal.
#pragma once

#include "PFCrypto/PFStatus.hpp" // pf::Status
#include "Secure.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>

namespace Botan {
class MessageAuthenticationCode;
class HashFunction;
} // namespace Botan

namespace pf::manifest {

// One computation of
//   manifest_mac = HMAC-SHA-256(k_manifest,
//                    vault_version(u64 BE) , Σ( uuid(16) , version(u64 BE) , SHA-256(sealed) ))
//
// vault_version is folded in by the constructor (first, matching §5.5). The
// caller feeds records in UUID-sorted order via update(); the Σ is just the
// concatenation of those rows, so *order is the caller's responsibility* and a
// different order yields a different MAC. finish() is single-shot.
class ManifestMac {
public:
    ManifestMac(const SecureBytes &k_manifest, uint64_t vault_version);
    ~ManifestMac();
    ManifestMac(const ManifestMac &) = delete;
    ManifestMac &operator=(const ManifestMac &) = delete;

    // SHA-256(sealed), then HMAC-update(uuid , version , that hash).
    // After finish() -> Status::BadInput. sealed==nullptr with len!=0 -> BadInput.
    Status update(const uint8_t uuid[16], uint64_t version, const uint8_t *sealed, size_t len);

    // The 32-byte MAC. A second call returns an empty vector.
    SecureBytes finish();
    bool finished() const noexcept { return finished_; }

private:
    std::unique_ptr<Botan::MessageAuthenticationCode> hmac_;
    std::unique_ptr<Botan::HashFunction> sha_;
    bool finished_ = false;
};

} // namespace pf::manifest
