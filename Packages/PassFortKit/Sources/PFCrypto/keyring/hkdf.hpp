// keyring/hkdf.hpp -- the HKDF subkey hierarchy (§5.1). Internal to PFCrypto.
#pragma once

#include "Secure.hpp"

#include <string_view>

namespace pf::keyring {

// Domain-separation labels. These are part of the on-disk format: a vault
// sealed with "pf-rec-v1" can only be opened with the same string. The -v1
// suffix leaves room for a future rotation. Pinned in architecture.md §5.1.
inline constexpr std::string_view kInfoKek = "pf-kek-v1";
inline constexpr std::string_view kInfoAuth = "pf-auth-v1";
inline constexpr std::string_view kInfoRecord = "pf-rec-v1";
inline constexpr std::string_view kInfoIndex = "pf-idx-v1";
inline constexpr std::string_view kInfoManifest = "pf-mft-v1";

// Expanded from the 64-byte Argon2id output. Live inside the Session handle and
// are scrubbed on close. auth_secret is sync-only (M5): it is the only key
// material a server ever sees (§5.1 caveat -- an offline-crackable verifier).
struct RootKeys {
    SecureBytes kek;         // 32 B
    SecureBytes auth_secret; // 32 B
};

// Derived from the unwrapped 32-byte DEK. k_index is used from M5 and
// k_manifest from M2; all three are derived together for simplicity.
struct DekSubkeys {
    SecureBytes k_record;   // 32 B -- record AEAD
    SecureBytes k_index;    // 32 B -- blind indexes (M5)
    SecureBytes k_manifest; // 32 B -- anti-rollback MAC
};

// HKDF-Expand (SHA-256), 32-byte outputs. Input is already a uniformly random
// key, so the extract step is skipped (RFC 5869 section 3.3). Throws
// Botan::Exception on failure.
RootKeys derive_root(const SecureBytes &argon64);
DekSubkeys derive_dek_subkeys(const SecureBytes &dek);

} // namespace pf::keyring
