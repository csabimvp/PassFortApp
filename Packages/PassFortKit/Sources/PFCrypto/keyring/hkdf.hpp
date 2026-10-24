// keyring/hkdf.hpp -- the HKDF subkey hierarchy (§5.1). Internal to PFCrypto.
#pragma once

#include "Secure.hpp"

#include <string_view>

namespace pf::keyring {

// Domain-separation labels. These are part of the on-disk format: a vault
// sealed with "pf-rec-v1" can only be opened with the same string. The -v1
// suffix leaves room for a future rotation. Pinned in architecture.md §5.1.
inline constexpr std::string_view kInfoKek = "pf-kek-v1";
inline constexpr std::string_view kInfoRecord = "pf-rec-v1";
inline constexpr std::string_view kInfoIndex = "pf-idx-v1";
inline constexpr std::string_view kInfoManifest = "pf-mft-v1";
inline constexpr std::string_view kInfoRecoveryKek = "pf-rk-v1"; // recovery-slot KEK (ADR-0007)
// The sync credential's label is fixed by ADR-0009 and the server contract
// (SyncAPI/openapi.yaml), hence no pf-/-v1 pattern. Not on-disk format: nothing in
// a vault file depends on it, only SHA-256(k_auth) registered on the server.
inline constexpr std::string_view kInfoSyncAuth = "sync-auth";

// Expanded from the 64-byte Argon2id output. Lives inside the Session handle and
// is scrubbed on close. The KEK is the only output since ADR-0009; the expand
// still reads all 64 bytes, so existing vaults' KEKs are unchanged.
struct RootKeys {
    SecureBytes kek; // 32 B
};

// Derived from the unwrapped 32-byte DEK, all together for simplicity. k_index
// has no reader yet (blind indexes are deferred, §14 #20). k_auth is the sync
// credential (ADR-0009) -- the one subkey that leaves C++, via
// pf_session_auth_key, because showing it to the server is its purpose.
struct DekSubkeys {
    SecureBytes k_record;   // 32 B -- record AEAD
    SecureBytes k_index;    // 32 B -- blind indexes (deferred)
    SecureBytes k_manifest; // 32 B -- anti-rollback MAC
    SecureBytes k_auth;     // 32 B -- sync login (ADR-0009)
};

// HKDF-Expand (SHA-256), 32-byte outputs. Input is already a uniformly random
// key, so the extract step is skipped (RFC 5869 section 3.3). Throws
// Botan::Exception on failure.
RootKeys derive_root(const SecureBytes &argon64);
DekSubkeys derive_dek_subkeys(const SecureBytes &dek);

// The recovery-slot KEK: HKDF-Expand(recovery_key, kInfoRecoveryKek) -> 32 B.
// `recovery_key` is 32 CSPRNG bytes -- already a full-strength key, so no Argon2
// (ADR-0007). Wraps the *same* DEK as the password slot.
SecureBytes derive_recovery_kek(const uint8_t recovery_key[32]);

} // namespace pf::keyring
