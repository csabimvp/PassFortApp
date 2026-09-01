// boundary/session.cpp -- noexcept POD facade over keyring/. No pf::keyring type
// appears in PFSession.hpp; the translation happens here (§6.1).
#include "PFCrypto/PFSession.hpp"

#include "Bytes.hpp"   // internal/ -- owned return buffers
#include "Limits.hpp"  // internal/ -- kMaxSeamInput
#include "Session.hpp" // internal/ -- the concrete Session
#include "botan_all.h"
#include "keyring/header.hpp"
#include "keyring/hkdf.hpp"
#include "keyring/kdf.hpp"

#include <array>
#include <cstring>
#include <span>
#include <utility>

namespace pf {

namespace {

keyring::KdfParams to_internal(const KdfParams &p) {
    keyring::KdfParams k;
    k.kdf_id = static_cast<uint8_t>(p.kdf_id);
    k.m_kib = p.m_kib;
    k.t = p.t;
    k.p = p.p;
    std::memcpy(k.salt, p.salt, sizeof k.salt);
    return k;
}

KdfParams to_pod(const keyring::KdfParams &k) {
    KdfParams p{};
    p.kdf_id = k.kdf_id;
    p.m_kib = k.m_kib;
    p.t = k.t;
    p.p = k.p;
    std::memcpy(p.salt, k.salt, sizeof p.salt);
    return p;
}

Bytes *header_bytes(const SecureBytes &h) { return new Bytes(h); }

bool bad_ptr(const uint8_t *p, size_t len) { return p == nullptr && len != 0; }
bool bad_len(size_t len) { return len > kMaxSeamInput; }

} // namespace

KdfResult pf_kdf_calibrate(uint32_t target_ms) noexcept {
    try {
        return {to_pod(keyring::calibrate(target_ms)), Status::Ok};
    } catch (...) {
        return {KdfParams{}, Status::Internal};
    }
}

BytesResult pf_vault_create(const uint8_t *pw, size_t pw_len, KdfParams params) noexcept {
    try {
        if (bad_ptr(pw, pw_len) || bad_len(pw_len))
            return {nullptr, Status::BadInput};

        const keyring::KdfParams kdf = to_internal(params);
        if (!keyring::kdf_params_sane(kdf))
            return {nullptr, Status::BadInput};

        SecureBytes dek(32);
        Botan::system_rng().randomize(dek);
        std::array<uint8_t, 16> vault_uuid{};
        Botan::system_rng().randomize(std::span<uint8_t>(vault_uuid.data(), vault_uuid.size()));

        keyring::RootKeys root;
        const SecureBytes header = keyring::header_encode(pw, pw_len, kdf, vault_uuid, dek, root);
        return {header_bytes(header), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

SessionResult pf_session_open(const uint8_t *header, size_t header_len, const uint8_t *pw,
                              size_t pw_len) noexcept {
    try {
        if (header == nullptr || header_len == 0 || bad_ptr(pw, pw_len))
            return {nullptr, Status::BadInput};
        if (bad_len(header_len) || bad_len(pw_len))
            return {nullptr, Status::BadInput};

        keyring::HeaderInfo info;
        SecureBytes dek;
        keyring::RootKeys root;
        const Status st = keyring::header_decode(header, header_len, pw, pw_len, info, dek, root);
        if (st != Status::Ok)
            return {nullptr, st};

        auto *s = new Session();
        s->vault_uuid = info.vault_uuid;
        s->kdf = info.kdf;
        s->root = std::move(root);
        s->dek = std::move(dek);
        s->sub = keyring::derive_dek_subkeys(s->dek);
        return {s, Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

BytesResult pf_session_rewrap(Session *s, const uint8_t *new_pw, size_t new_pw_len) noexcept {
    try {
        if (s == nullptr || bad_ptr(new_pw, new_pw_len) || bad_len(new_pw_len))
            return {nullptr, Status::BadInput};
        if (!s->alive())
            return {nullptr, Status::Locked};

        keyring::KdfParams kdf = s->kdf; // same cost, fresh salt
        Botan::system_rng().randomize(std::span<uint8_t>(kdf.salt, sizeof kdf.salt));

        keyring::RootKeys root;
        const SecureBytes header =
            keyring::header_encode(new_pw, new_pw_len, kdf, s->vault_uuid, s->dek, root);

        // Only the old KEK / auth_secret are stale. DEK and its subkeys are
        // unchanged -- re-wrap re-encrypts 32 bytes, it does not re-key the vault.
        pf::scrub(s->root.kek);
        pf::scrub(s->root.auth_secret);
        s->kdf = kdf;
        s->root = std::move(root);
        return {header_bytes(header), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

BytesResult pf_recovery_wrap(Session *s, const uint8_t *recovery_key) noexcept {
    try {
        if (s == nullptr || recovery_key == nullptr)
            return {nullptr, Status::BadInput};
        if (!s->alive())
            return {nullptr, Status::Locked};
        // A recovery-opened session has no password KEK; it must rewrap to a
        // password before it can add a (new) recovery slot.
        if (s->root.kek.size() != 32)
            return {nullptr, Status::BadInput};

        const SecureBytes header = keyring::header_encode_with_recovery(
            s->kdf, s->vault_uuid, s->dek, s->root.kek, recovery_key);
        return {header_bytes(header), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

SessionResult pf_recovery_open(const uint8_t *header, size_t header_len,
                               const uint8_t *recovery_key) noexcept {
    try {
        if (header == nullptr || header_len == 0 || recovery_key == nullptr)
            return {nullptr, Status::BadInput};
        if (bad_len(header_len))
            return {nullptr, Status::BadInput};

        keyring::HeaderInfo info;
        SecureBytes dek;
        const Status st =
            keyring::header_decode_recovery(header, header_len, recovery_key, info, dek);
        if (st != Status::Ok)
            return {nullptr, st};

        auto *s = new Session();
        s->vault_uuid = info.vault_uuid;
        s->kdf = info.kdf;
        // No password RootKeys -- a recovery session must rewrap to a password
        // before sync (M5). root stays default (empty SecureBytes).
        s->dek = std::move(dek);
        s->sub = keyring::derive_dek_subkeys(s->dek);
        return {s, Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

Status pf_session_vault_uuid(Session *s, uint8_t *out) noexcept {
    if (s == nullptr || out == nullptr)
        return Status::BadInput;
    if (!s->alive())
        return Status::Locked;
    std::memcpy(out, s->vault_uuid.data(), s->vault_uuid.size());
    return Status::Ok;
}

void pf_session_close(Session *s) noexcept {
    if (s == nullptr)
        return;
    s->magic = 0; // trip alive() for any subsequent boundary call on this handle
    s->scrub();
    delete s;
}

} // namespace pf
