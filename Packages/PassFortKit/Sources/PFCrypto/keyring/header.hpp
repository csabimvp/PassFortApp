// keyring/header.hpp -- the §5.3 vault-header codec. Internal to PFCrypto.
#pragma once

#include "PFCrypto/PFStatus.hpp" // pf::Status
#include "Secure.hpp"
#include "keyring/hkdf.hpp" // RootKeys
#include "keyring/kdf.hpp"  // KdfParams

#include <array>
#include <cstddef>
#include <cstdint>

namespace pf::keyring {

// The plaintext fields of a decoded header (§5.3). The wrapped DEK is not here:
// the decode functions hand back the *unwrapped* DEK, or a status.
struct HeaderInfo {
    uint16_t format_version = 0;
    std::array<uint8_t, 16> vault_uuid{};
    KdfParams kdf{};
    uint8_t wrap_alg = 0;
    uint8_t slot_count = 1; // 1 = password only, 2 = password + recovery key (ADR-0007)
    int64_t created_at = 0;
};

// Header sizes (§5.3, ADR-0007): a 53-byte fixed prefix (magic .. slot_count),
// then `slot_count` * 72-byte slots (nonce 24 , wrapped_dek 32 , tag 16), then an
// 8-byte created_at. The prefix, including slot_count, is the AEAD's AAD for
// *every* slot -- so a stripped slot fails the tag check.
inline constexpr size_t kHeaderLen = 133;             // slot_count == 1
inline constexpr size_t kHeaderLenWithRecovery = 205; // slot_count == 2

// Serialize a password-only (slot_count == 1) header. Derives the KEK from
// (pw, kdf), wraps `dek` (must be 32 bytes) under it with XChaCha20-Poly1305, AAD
// = the 53-byte prefix. `root_out` receives the derived keys so the caller can
// open a session without a second Argon2 pass. Throws Botan::Exception on failure.
SecureBytes header_encode(const uint8_t *pw, size_t pw_len, const KdfParams &kdf,
                          const std::array<uint8_t, 16> &vault_uuid, const SecureBytes &dek,
                          RootKeys &root_out);

// Serialize a two-slot (slot_count == 2) header wrapping the *same* `dek` under
// both the password KEK (passed in -- no Argon2 here) and a KEK derived from
// `recovery_key` (32 CSPRNG bytes) via HKDF (`kInfoRecoveryKek`). Used by
// pf_recovery_wrap once the caller is already unlocked. Throws on failure.
SecureBytes header_encode_with_recovery(const KdfParams &kdf,
                                        const std::array<uint8_t, 16> &vault_uuid,
                                        const SecureBytes &dek, const SecureBytes &password_kek,
                                        const uint8_t recovery_key[32]);

// Parse and verify a header against `pw` (slot 0). On success fills `info`,
// `dek_out` (the 32-byte unwrapped DEK) and `root_out`, and returns Status::Ok.
//   - wrong password or any tampering -> Status::AuthFailed  (no oracle, §13.1)
//   - buffer too short / bad magic     -> Status::BadInput
//   - unknown format_version/kdf_id/wrap_alg/slot_count -> Status::Unsupported
Status header_decode(const uint8_t *header, size_t header_len, const uint8_t *pw, size_t pw_len,
                     HeaderInfo &info, SecureBytes &dek_out, RootKeys &root_out);

// Parse and verify a header against `recovery_key` (slot 1). No Argon2 -- the KEK
// is HKDF(recovery_key). Fills `info` and `dek_out`; there is no password-derived
// RootKeys, so a recovery session must re-wrap to a password before it can sync.
//   - slot_count != 2 (no recovery slot) -> Status::NotFound
//   - wrong key or tampering              -> Status::AuthFailed
//   - buffer too short / bad magic        -> Status::BadInput
Status header_decode_recovery(const uint8_t *header, size_t header_len,
                              const uint8_t recovery_key[32], HeaderInfo &info,
                              SecureBytes &dek_out);

} // namespace pf::keyring
