// keyring/header.cpp -- see header.hpp.
#include "keyring/header.hpp"

#include "Canonical.hpp"
#include "botan_all.h"

#include <chrono>
#include <cstring>
#include <span>

namespace pf::keyring {

namespace {

constexpr uint8_t kMagic[4] = {'P', 'F', 'V', 0x01};
constexpr uint16_t kFormatVersion = 1;
constexpr uint8_t kKdfArgon2id = 1;
constexpr uint8_t kWrapXChaCha = 1;
constexpr size_t kDekLen = 32;
constexpr size_t kNonceLen = 24;
constexpr size_t kTagLen = 16;

// Offset where slot bytes (nonce , wrapped_dek , tag) begin -- everything before
// this is the AEAD's AAD, so the tag also authenticates the KDF parameters.
constexpr size_t kAadLen = 4 + 2 + 16 + 1 + 4 + 4 + 4 + 16 + 1; // = 52
constexpr size_t kSlotLen = kNonceLen + kDekLen + kTagLen;      // = 64

static_assert(kAadLen + kSlotLen + 8 == kHeaderLen, "header layout drift");

// Big-endian readers. Callers bounds-check the buffer first.
uint16_t rd_u16(const uint8_t *p) { return static_cast<uint16_t>(p[0] << 8 | p[1]); }
uint32_t rd_u32(const uint8_t *p) {
    return static_cast<uint32_t>(p[0]) << 24 | static_cast<uint32_t>(p[1]) << 16 |
           static_cast<uint32_t>(p[2]) << 8 | p[3];
}
uint64_t rd_u64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; ++i)
        v = v << 8 | p[i];
    return v;
}

int64_t now_epoch_seconds() {
    return std::chrono::duration_cast<std::chrono::seconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

} // namespace

SecureBytes header_encode(const uint8_t *pw, size_t pw_len, const KdfParams &kdf,
                          const std::array<uint8_t, 16> &vault_uuid, const SecureBytes &dek,
                          RootKeys &root_out) {
    if (dek.size() != kDekLen)
        throw Botan::Invalid_Argument("header_encode: DEK must be 32 bytes");

    SecureBytes out;
    canon::put_bytes(out, kMagic, sizeof kMagic);
    canon::put_u16(out, kFormatVersion);
    canon::put_bytes(out, vault_uuid.data(), vault_uuid.size());
    canon::put_u8(out, kKdfArgon2id);
    canon::put_u32(out, kdf.m_kib);
    canon::put_u32(out, kdf.t);
    canon::put_u32(out, kdf.p);
    canon::put_bytes(out, kdf.salt, sizeof kdf.salt);
    canon::put_u8(out, kWrapXChaCha);

    // AAD = every header byte up to here (magic .. wrap_alg). Binds the KDF
    // params into the tag so a downgraded-parameter header fails to unwrap.
    // The nonce is bound by the AEAD construction itself, so it is not repeated
    // here -- kAadLen must stay in sync with header_decode.
    const SecureBytes aad(out.begin(), out.end());

    SecureBytes nonce(kNonceLen);
    Botan::system_rng().randomize(nonce);
    canon::put_bytes(out, nonce.data(), nonce.size());

    const SecureBytes argon64 = argon2id_64(pw, pw_len, kdf);
    root_out = derive_root(argon64);

    auto enc = Botan::AEAD_Mode::create_or_throw("ChaCha20Poly1305", Botan::Cipher_Dir::Encryption);
    enc->set_key(root_out.kek);
    enc->set_associated_data(aad);
    enc->start(nonce);
    SecureBytes wrapped(dek.begin(), dek.end());
    enc->finish(wrapped); // -> ciphertext(32) , tag(16)

    canon::put_bytes(out, wrapped.data(), wrapped.size());
    canon::put_u64(out, static_cast<uint64_t>(now_epoch_seconds()));
    return out;
}

Status header_decode(const uint8_t *header, size_t header_len, const uint8_t *pw, size_t pw_len,
                     HeaderInfo &info, SecureBytes &dek_out, RootKeys &root_out) {
    if (header == nullptr || header_len < kHeaderLen)
        return Status::BadInput;
    if (std::memcmp(header, kMagic, sizeof kMagic) != 0)
        return Status::BadInput;

    size_t off = sizeof kMagic;
    const uint16_t format_version = rd_u16(header + off);
    off += 2;
    if (format_version != kFormatVersion)
        return Status::Unsupported;

    HeaderInfo parsed;
    parsed.format_version = format_version;
    std::memcpy(parsed.vault_uuid.data(), header + off, 16);
    off += 16;

    parsed.kdf.kdf_id = header[off];
    off += 1;
    parsed.kdf.m_kib = rd_u32(header + off);
    off += 4;
    parsed.kdf.t = rd_u32(header + off);
    off += 4;
    parsed.kdf.p = rd_u32(header + off);
    off += 4;
    std::memcpy(parsed.kdf.salt, header + off, 16);
    off += 16;
    if (parsed.kdf.kdf_id != kKdfArgon2id)
        return Status::Unsupported;
    // Reject a tampered / foreign header whose KDF params would make Argon2 run
    // for hours or exhaust memory -- before we call it. A wrong-but-plausible
    // param is still caught by the AAD tag check below; both surface as
    // AuthFailed, so this adds no oracle.
    if (!kdf_params_sane(parsed.kdf))
        return Status::AuthFailed;

    parsed.wrap_alg = header[off];
    off += 1;
    if (parsed.wrap_alg != kWrapXChaCha)
        return Status::Unsupported;

    const uint8_t *nonce = header + off;
    off += kNonceLen;
    const uint8_t *wrapped = header + off; // ciphertext(32) , tag(16)
    off += kDekLen + kTagLen;
    parsed.created_at = static_cast<int64_t>(rd_u64(header + off));

    const SecureBytes argon64 = argon2id_64(pw, pw_len, parsed.kdf);
    const RootKeys root = derive_root(argon64);

    SecureBytes dek(wrapped, wrapped + kDekLen + kTagLen);
    try {
        auto dec =
            Botan::AEAD_Mode::create_or_throw("ChaCha20Poly1305", Botan::Cipher_Dir::Decryption);
        dec->set_key(root.kek);
        dec->set_associated_data(std::span<const uint8_t>(header, kAadLen));
        dec->start(std::span<const uint8_t>(nonce, kNonceLen));
        dec->finish(dek);
    } catch (const Botan::Invalid_Authentication_Tag &) {
        return Status::AuthFailed; // wrong password OR tampered header -- same code
    }
    if (dek.size() != kDekLen)
        return Status::AuthFailed;

    info = parsed;
    dek_out = std::move(dek);
    root_out = root;
    return Status::Ok;
}

} // namespace pf::keyring
