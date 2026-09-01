// boundary/manifest.cpp -- noexcept POD facade for pf_mac_*. Same discipline as
// session.cpp / record.cpp.
#include "PFCrypto/PFManifest.hpp"

#include "Bytes.hpp"   // internal/
#include "Limits.hpp"  // internal/
#include "Session.hpp" // internal/
#include "manifest/manifest_mac.hpp"

#include <utility>

namespace pf {

// Opaque handle -- defined here, never in a public header (§6.1 rule 3).
struct Mac {
    static constexpr uint32_t kLiveMagic = 0x50464d31; // 'PFM1'
    uint32_t magic = kLiveMagic;
    manifest::ManifestMac impl;

    Mac(const SecureBytes &k_manifest, uint64_t vault_version) : impl(k_manifest, vault_version) {}

    bool alive() const noexcept { return magic == kLiveMagic; }
};

MacResult pf_mac_init(Session *s, uint64_t vault_version) noexcept {
    try {
        if (s == nullptr)
            return {nullptr, Status::BadInput};
        if (!s->alive())
            return {nullptr, Status::Locked};
        return {new Mac(s->sub.k_manifest, vault_version), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

Status pf_mac_update(Mac *m, const uint8_t *record_uuid, uint64_t version, const uint8_t *sealed,
                     size_t sealed_len) noexcept {
    try {
        if (m == nullptr || record_uuid == nullptr || !m->alive())
            return Status::BadInput;
        if (sealed_len > kMaxSeamInput)
            return Status::BadInput;
        return m->impl.update(record_uuid, version, sealed, sealed_len);
    } catch (...) {
        return Status::Internal;
    }
}

BytesResult pf_mac_finish(Mac *m) noexcept {
    try {
        if (m == nullptr || !m->alive() || m->impl.finished())
            return {nullptr, Status::BadInput};
        SecureBytes mac = m->impl.finish();
        if (mac.size() != 32)
            return {nullptr, Status::Internal};
        return {new Bytes(std::move(mac)), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

void pf_mac_free(Mac *m) noexcept {
    if (m == nullptr)
        return;
    m->magic = 0;
    delete m;
}

} // namespace pf
