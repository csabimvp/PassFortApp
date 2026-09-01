// internal/Session.hpp -- the concrete pf::Session. NOT exported (sibling of
// include/, not under it). boundary/session.cpp builds it; boundary/record.cpp
// and boundary/manifest.cpp read its subkeys. Swift only ever sees `Session*`.
#pragma once

#include "Secure.hpp"
#include "keyring/hkdf.hpp"
#include "keyring/kdf.hpp"

#include <array>
#include <cstdint>

namespace pf {

// Every secret field is SecureBytes and scrubs on destruction; scrub() forces
// zeroization of the whole set before `delete` in pf_session_close (§6.2).
struct Session {
    // Liveness sentinel. pf_session_close clears it before delete, so a boundary
    // call on a stale handle returns Locked instead of touching freed keys.
    // Best-effort only -- once the freed memory is reused this is undefined
    // behaviour, which C cannot fix (§13 seam-fuzz note).
    static constexpr uint32_t kLiveMagic = 0x50465331; // 'PFS1'
    uint32_t magic = kLiveMagic;

    std::array<uint8_t, 16> vault_uuid{};
    keyring::KdfParams kdf{};
    keyring::RootKeys root;  // kek, auth_secret
    SecureBytes dek;         // 32B, unwrapped
    keyring::DekSubkeys sub; // k_record, k_index, k_manifest

    bool alive() const noexcept { return magic == kLiveMagic; }

    void scrub() noexcept {
        pf::scrub(root.kek);
        pf::scrub(root.auth_secret);
        pf::scrub(dek);
        pf::scrub(sub.k_record);
        pf::scrub(sub.k_index);
        pf::scrub(sub.k_manifest);
    }
};

} // namespace pf
