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
// header_decode hands back the *unwrapped* DEK, or a status.
struct HeaderInfo {
    uint16_t format_version = 0;
    std::array<uint8_t, 16> vault_uuid{};
    KdfParams kdf{};
    uint8_t wrap_alg = 0;
    int64_t created_at = 0;
};

// Total size of a v1 header: fixed layout, no variable fields.
inline constexpr size_t kHeaderLen = 132;

// Serialize a v1 header. Derives the KEK from (pw, kdf), wraps `dek` (must be 32
// bytes) with XChaCha20-Poly1305 using every preceding header byte as AAD, and
// appends wrap_nonce , wrapped_dek , tag , created_at. `root_out` receives the
// derived keys so the caller can open a session without a second Argon2 pass.
// Throws Botan::Exception on failure.
SecureBytes header_encode(const uint8_t *pw, size_t pw_len, const KdfParams &kdf,
                          const std::array<uint8_t, 16> &vault_uuid, const SecureBytes &dek,
                          RootKeys &root_out);

// Parse and verify a header against `pw`. On success fills `info`, `dek_out`
// (the 32-byte unwrapped DEK) and `root_out`, and returns Status::Ok.
//   - wrong password or any tampering -> Status::AuthFailed  (no oracle, §13.1)
//   - buffer too short / bad magic     -> Status::BadInput
//   - unknown format_version/kdf_id/wrap_alg -> Status::Unsupported
Status header_decode(const uint8_t *header, size_t header_len, const uint8_t *pw, size_t pw_len,
                     HeaderInfo &info, SecureBytes &dek_out, RootKeys &root_out);

} // namespace pf::keyring
