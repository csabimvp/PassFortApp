// keyring/kdf.hpp -- Argon2id + machine calibration. Internal to PFCrypto.
#pragma once

#include "Secure.hpp"

#include <cstddef>
#include <cstdint>

namespace pf::keyring {

// POD parameter set. Mirrors the seam struct in PFSession.hpp (§7.4) and the
// KDF fields of the vault header (§5.3). `salt` is per-vault, drawn from the OS
// CSPRNG at vault-create time; m_kib/t/p are what calibrate() measured for this
// machine and travel with the vault so a slow machine opens it at the stored
// cost, not a re-measured one (§5.2).
struct KdfParams {
    uint8_t kdf_id = 1; // 1 = Argon2id (the only value in M1)
    uint32_t m_kib = 0; // memory cost, KiB
    uint32_t t = 0;     // time cost (passes)
    uint32_t p = 0;     // parallelism (lanes)
    uint8_t salt[16] = {};
};

// Argon2id(password, params.salt) with params.{m_kib,t,p} -> 64 bytes.
// The 64 bytes are the single expensive KDF output that hkdf.hpp expands into
// the KEK and auth_secret (§5.1). Throws Botan::Exception on invalid params.
SecureBytes argon2id_64(const uint8_t *pw, size_t pw_len, const KdfParams &params);

// Measure Argon2id on THIS machine and return params that take ~target_ms.
// t and p are pinned to 3 and 4 (§5.2); only m_kib is chosen, clamped to
// [64 MiB, 4 GiB]. `salt` is filled with 16 fresh bytes from the OS CSPRNG.
KdfParams calibrate(uint32_t target_ms);

} // namespace pf::keyring
