// manifest/manifest_mac.cpp -- see manifest_mac.hpp.
#include "manifest/manifest_mac.hpp"

#include "Canonical.hpp"
#include "botan_all.h"

namespace pf::manifest {

ManifestMac::ManifestMac(const SecureBytes &k_manifest, uint64_t vault_version)
    : hmac_(Botan::MessageAuthenticationCode::create_or_throw("HMAC(SHA-256)")),
      sha_(Botan::HashFunction::create_or_throw("SHA-256")) {
    hmac_->set_key(k_manifest);

    // vault_version(u64 BE) goes in first -- §5.5:
    //   HMAC(k_manifest, vault_version , Σ_sorted(uuid , version , SHA-256(ct)))
    SecureBytes v;
    canon::put_u64(v, vault_version);
    hmac_->update(v);
}

ManifestMac::~ManifestMac() = default;

Status ManifestMac::update(const uint8_t uuid[16], uint64_t version, const uint8_t *sealed,
                           size_t len) {
    if (finished_)
        return Status::BadInput;
    if (sealed == nullptr && len != 0)
        return Status::BadInput;

    if (len != 0)
        sha_->update(sealed, len);
    const SecureBytes digest = sha_->final(); // 32B; the hash object resets itself

    SecureBytes row;
    row.reserve(16 + 8 + digest.size());
    canon::put_bytes(row, uuid, 16);
    canon::put_u64(row, version);
    canon::put_bytes(row, digest.data(), digest.size());
    hmac_->update(row);
    return Status::Ok;
}

SecureBytes ManifestMac::finish() {
    if (finished_)
        return {};
    finished_ = true;
    return hmac_->final(); // 32B
}

} // namespace pf::manifest
