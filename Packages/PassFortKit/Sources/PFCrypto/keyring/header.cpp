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

// The fixed prefix -- magic .. slot_count -- is the AEAD's AAD for every slot, so
// the tag authenticates the KDF parameters *and* slot_count (a stripped slot
// fails to unwrap). The nonce is bound by the AEAD construction itself and is not
// repeated in the AAD.
constexpr size_t kPrefixLen =
    4 + 2 + 16 + 1 + 4 + 4 + 4 + 16 + 1 + 1;               // = 53 (slot_count is byte 52)
constexpr size_t kSlotLen = kNonceLen + kDekLen + kTagLen; // = 72
constexpr size_t kCreatedAtLen = 8;

constexpr size_t header_size(uint8_t slot_count) {
    return kPrefixLen + static_cast<size_t>(slot_count) * kSlotLen + kCreatedAtLen;
}
static_assert(header_size(1) == kHeaderLen, "1-slot header layout drift");
static_assert(header_size(2) == kHeaderLenWithRecovery, "2-slot header layout drift");

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

// magic .. slot_count -- kPrefixLen bytes, identical shape for encode and decode.
void put_prefix(SecureBytes &out, const KdfParams &kdf, const std::array<uint8_t, 16> &vault_uuid,
                uint8_t slot_count) {
    canon::put_bytes(out, kMagic, sizeof kMagic);
    canon::put_u16(out, kFormatVersion);
    canon::put_bytes(out, vault_uuid.data(), vault_uuid.size());
    canon::put_u8(out, kKdfArgon2id);
    canon::put_u32(out, kdf.m_kib);
    canon::put_u32(out, kdf.t);
    canon::put_u32(out, kdf.p);
    canon::put_bytes(out, kdf.salt, sizeof kdf.salt);
    canon::put_u8(out, kWrapXChaCha);
    canon::put_u8(out, slot_count);
}

// Append one slot -- nonce(24) , wrapped_dek(32) , tag(16) -- wrapping `dek`
// under `kek` with `aad`.
void append_slot(SecureBytes &out, const SecureBytes &kek, const SecureBytes &dek,
                 std::span<const uint8_t> aad) {
    SecureBytes nonce(kNonceLen);
    Botan::system_rng().randomize(nonce);

    auto enc = Botan::AEAD_Mode::create_or_throw("ChaCha20Poly1305", Botan::Cipher_Dir::Encryption);
    enc->set_key(kek);
    enc->set_associated_data(aad);
    enc->start(nonce);
    SecureBytes wrapped(dek.begin(), dek.end());
    enc->finish(wrapped); // -> ciphertext(32) , tag(16)

    canon::put_bytes(out, nonce.data(), nonce.size());
    canon::put_bytes(out, wrapped.data(), wrapped.size());
}

// Try to unwrap the slot at `slot` (kSlotLen bytes) under `kek` with `aad`.
// A wrong KEK or any tampering surfaces as AuthFailed -- no oracle.
Status unwrap_slot(const uint8_t *slot, const SecureBytes &kek, std::span<const uint8_t> aad,
                   SecureBytes &dek_out) {
    const uint8_t *nonce = slot;
    const uint8_t *wrapped = slot + kNonceLen; // ciphertext(32) , tag(16)
    SecureBytes dek(wrapped, wrapped + kDekLen + kTagLen);
    try {
        auto dec =
            Botan::AEAD_Mode::create_or_throw("ChaCha20Poly1305", Botan::Cipher_Dir::Decryption);
        dec->set_key(kek);
        dec->set_associated_data(aad);
        dec->start(std::span<const uint8_t>(nonce, kNonceLen));
        dec->finish(dek);
    } catch (const Botan::Invalid_Authentication_Tag &) {
        return Status::AuthFailed;
    }
    if (dek.size() != kDekLen)
        return Status::AuthFailed;
    dek_out = std::move(dek);
    return Status::Ok;
}

// Parse the plaintext prefix fields into `parsed`. Returns Ok, or a status for a
// short buffer / bad magic / unsupported constant. Does not touch the slots.
Status parse_prefix(const uint8_t *header, size_t header_len, HeaderInfo &parsed) {
    if (header == nullptr || header_len < kHeaderLen)
        return Status::BadInput;
    if (std::memcmp(header, kMagic, sizeof kMagic) != 0)
        return Status::BadInput;

    size_t off = sizeof kMagic;
    parsed.format_version = rd_u16(header + off);
    off += 2;
    if (parsed.format_version != kFormatVersion)
        return Status::Unsupported;

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

    parsed.wrap_alg = header[off];
    off += 1;
    if (parsed.wrap_alg != kWrapXChaCha)
        return Status::Unsupported;

    parsed.slot_count = header[off]; // kSlotCountOffset
    off += 1;
    if (parsed.slot_count != 1 && parsed.slot_count != 2)
        return Status::Unsupported;
    if (header_len < header_size(parsed.slot_count))
        return Status::BadInput;

    // A tampered / foreign header whose KDF params would make Argon2 run for
    // hours or exhaust memory is rejected before we call it. A wrong-but-plausible
    // param is still caught by the AAD tag check; both surface as AuthFailed, so
    // this adds no oracle.
    if (!kdf_params_sane(parsed.kdf))
        return Status::AuthFailed;

    parsed.created_at = static_cast<int64_t>(
        rd_u64(header + kPrefixLen + static_cast<size_t>(parsed.slot_count) * kSlotLen));
    return Status::Ok;
}

} // namespace

SecureBytes header_encode(const uint8_t *pw, size_t pw_len, const KdfParams &kdf,
                          const std::array<uint8_t, 16> &vault_uuid, const SecureBytes &dek,
                          RootKeys &root_out) {
    if (dek.size() != kDekLen)
        throw Botan::Invalid_Argument("header_encode: DEK must be 32 bytes");

    SecureBytes out;
    put_prefix(out, kdf, vault_uuid, /*slot_count=*/1);
    const SecureBytes aad(out.begin(), out.end()); // kPrefixLen bytes

    const SecureBytes argon64 = argon2id_64(pw, pw_len, kdf);
    root_out = derive_root(argon64);

    append_slot(out, root_out.kek, dek, aad);
    canon::put_u64(out, static_cast<uint64_t>(now_epoch_seconds()));
    return out;
}

SecureBytes header_encode_with_recovery(const KdfParams &kdf,
                                        const std::array<uint8_t, 16> &vault_uuid,
                                        const SecureBytes &dek, const SecureBytes &password_kek,
                                        const uint8_t recovery_key[32]) {
    if (dek.size() != kDekLen)
        throw Botan::Invalid_Argument("header_encode_with_recovery: DEK must be 32 bytes");
    if (password_kek.size() != 32)
        throw Botan::Invalid_Argument("header_encode_with_recovery: password KEK must be 32 bytes");

    SecureBytes out;
    put_prefix(out, kdf, vault_uuid, /*slot_count=*/2);
    const SecureBytes aad(out.begin(), out.end());

    append_slot(out, password_kek, dek, aad); // slot 0 -- password
    const SecureBytes recovery_kek = derive_recovery_kek(recovery_key);
    append_slot(out, recovery_kek, dek, aad); // slot 1 -- recovery key

    canon::put_u64(out, static_cast<uint64_t>(now_epoch_seconds()));
    return out;
}

Status header_decode(const uint8_t *header, size_t header_len, const uint8_t *pw, size_t pw_len,
                     HeaderInfo &info, SecureBytes &dek_out, RootKeys &root_out) {
    HeaderInfo parsed;
    if (const Status st = parse_prefix(header, header_len, parsed); st != Status::Ok)
        return st;

    const SecureBytes argon64 = argon2id_64(pw, pw_len, parsed.kdf);
    RootKeys root = derive_root(argon64);

    SecureBytes dek;
    const Status st = unwrap_slot(header + kPrefixLen, root.kek,
                                  std::span<const uint8_t>(header, kPrefixLen), dek);
    if (st != Status::Ok)
        return st;

    info = parsed;
    dek_out = std::move(dek);
    root_out = std::move(root);
    return Status::Ok;
}

Status header_decode_recovery(const uint8_t *header, size_t header_len,
                              const uint8_t recovery_key[32], HeaderInfo &info,
                              SecureBytes &dek_out) {
    HeaderInfo parsed;
    if (const Status st = parse_prefix(header, header_len, parsed); st != Status::Ok)
        return st;
    if (parsed.slot_count != 2)
        return Status::NotFound; // this vault has no recovery slot

    const SecureBytes recovery_kek = derive_recovery_kek(recovery_key);
    SecureBytes dek;
    const Status st = unwrap_slot(header + kPrefixLen + kSlotLen, recovery_kek,
                                  std::span<const uint8_t>(header, kPrefixLen), dek); // slot 1
    if (st != Status::Ok)
        return st;

    info = parsed;
    dek_out = std::move(dek);
    return Status::Ok;
}

} // namespace pf::keyring
