// include/PFCrypto/PFSession.hpp -- PUBLIC. Session lifecycle + record crypto:
// keys are born and die inside these functions (§6.2). POD in, POD or opaque
// handle out.
#pragma once

#include "PFBytes.hpp" // BytesResult
#include "PFStatus.hpp"

#include <cstddef>
#include <cstdint>

// Nullability is annotated only on the opaque Session* -- Swift's importer reads
// it to force a `guard let` on a result handle and to allow nil at close. Raw
// (pointer, length) byte inputs are left unannotated (Swift imports them as
// implicitly-unwrapped optionals, matching PFBytes.hpp) because "null + zero
// length" is a legal input every function below handles. `_Nullable` is a Clang
// extension; keep -Wpedantic -Werror (the CMake build) quiet about it.
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

// Opaque -- defined in internal/Session.hpp, reachable only through these calls.
struct Session;

struct SessionResult {
    Session *PF_NULLABLE handle; // nil on failure
    Status status;
};

// POD mirror of keyring::KdfParams (§7.4). Fixed-width fields only -- this is
// what crosses the seam.
struct KdfParams {
    int32_t kdf_id; // 1 = argon2id
    uint32_t m_kib;
    uint32_t t;
    uint32_t p;
    uint8_t salt[16];
};

struct KdfResult {
    KdfParams params;
    Status status;
};

// Measure Argon2id on this machine; params.salt is filled from the OS CSPRNG.
KdfResult pf_kdf_calibrate(uint32_t target_ms) noexcept;

// Create a vault: random DEK + vault UUID, wrapped under `params`. Returns the
// §5.3 header blob. Does not open a session.
BytesResult pf_vault_create(const uint8_t *pw, size_t pw_len, KdfParams params) noexcept;

// Open a session from a header + password. Wrong password and a corrupt header
// both return {nil, AuthFailed} -- no oracle (§13.1).
SessionResult pf_session_open(const uint8_t *header, size_t header_len, const uint8_t *pw,
                              size_t pw_len) noexcept;

// Re-wrap the same DEK under a new password (same KDF cost, fresh salt).
// Returns a new header blob; the in-memory session switches to the new keys.
BytesResult pf_session_rewrap(Session *PF_NONNULL s, const uint8_t *new_pw,
                              size_t new_pw_len) noexcept;

// Zeroize RootKeys + DEK + DekSubkeys and free. Safe on nil (no-op).
void pf_session_close(Session *PF_NULLABLE s) noexcept;

// -- record crypto (§5.4) --------------------------------------------------
// The AAD (vault_uuid , record_uuid , version , schema) is assembled inside
// C++; the vault_uuid comes from the session, so Swift passes only the three
// per-record identity fields. Wrong key / wrong identity / tampered bytes all
// return AuthFailed. A stale session handle returns Locked.

// plaintext -> sealed blob (nonce , ciphertext , tag).
BytesResult pf_seal(Session *PF_NONNULL s, const uint8_t *record_uuid, uint64_t version,
                    uint16_t schema, const uint8_t *plaintext, size_t pt_len) noexcept;

// sealed blob -> plaintext. The returned Bytes is SecureBytes-backed, so
// pf_bytes_free scrubs the decrypted plaintext.
BytesResult pf_open(Session *PF_NONNULL s, const uint8_t *record_uuid, uint64_t version,
                    uint16_t schema, const uint8_t *sealed, size_t sealed_len) noexcept;

} // namespace pf

#undef PF_NULLABLE
#undef PF_NONNULL
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
