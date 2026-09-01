// aead/record_crypto.cpp -- see record_crypto.hpp.
#include "aead/record_crypto.hpp"

#include "Canonical.hpp"
#include "botan_all.h"

#include <span>

namespace pf::aead {

namespace {

constexpr size_t kNonceLen = 24;
constexpr size_t kTagLen = 16;

SecureBytes build_aad(const uint8_t vault_uuid[16], const uint8_t record_uuid[16], uint64_t version,
                      uint16_t schema) {
    SecureBytes aad;
    aad.reserve(16 + 16 + 8 + 2);
    canon::put_bytes(aad, vault_uuid, 16);
    canon::put_bytes(aad, record_uuid, 16);
    canon::put_u64(aad, version);
    canon::put_u16(aad, schema);
    return aad;
}

} // namespace

SecureBytes seal(const SecureBytes &k_record, const uint8_t vault_uuid[16],
                 const uint8_t record_uuid[16], uint64_t version, uint16_t schema,
                 const uint8_t *plaintext, size_t pt_len) {
    const SecureBytes aad = build_aad(vault_uuid, record_uuid, version, schema);

    SecureBytes nonce(kNonceLen);
    Botan::system_rng().randomize(nonce);

    auto enc = Botan::AEAD_Mode::create_or_throw("ChaCha20Poly1305", Botan::Cipher_Dir::Encryption);
    enc->set_key(k_record);
    enc->set_associated_data(aad);
    enc->start(nonce);

    SecureBytes buf;
    if (pt_len != 0)
        buf.assign(plaintext, plaintext + pt_len);
    enc->finish(buf); // buf -> ciphertext , tag

    SecureBytes sealed;
    sealed.reserve(kNonceLen + buf.size());
    sealed.insert(sealed.end(), nonce.begin(), nonce.end());
    sealed.insert(sealed.end(), buf.begin(), buf.end());
    return sealed;
}

Status open(const SecureBytes &k_record, const uint8_t vault_uuid[16],
            const uint8_t record_uuid[16], uint64_t version, uint16_t schema, const uint8_t *sealed,
            size_t sealed_len, SecureBytes &plaintext_out) {
    if (sealed == nullptr || sealed_len < kNonceLen + kTagLen)
        return Status::BadInput;

    const SecureBytes aad = build_aad(vault_uuid, record_uuid, version, schema);
    const uint8_t *nonce = sealed;
    const uint8_t *ct = sealed + kNonceLen;
    const size_t ct_len = sealed_len - kNonceLen;

    SecureBytes buf(ct, ct + ct_len);
    try {
        auto dec =
            Botan::AEAD_Mode::create_or_throw("ChaCha20Poly1305", Botan::Cipher_Dir::Decryption);
        dec->set_key(k_record);
        dec->set_associated_data(aad);
        dec->start(std::span<const uint8_t>(nonce, kNonceLen));
        dec->finish(buf); // throws Invalid_Authentication_Tag on any mismatch
    } catch (const Botan::Invalid_Authentication_Tag &) {
        return Status::AuthFailed;
    }
    plaintext_out = std::move(buf);
    return Status::Ok;
}

} // namespace pf::aead
