// boundary/record.cpp -- noexcept POD facade for pf_seal / pf_open. Same
// discipline as session.cpp: try/catch -> Status, POD in, opaque Bytes out.
#include "PFCrypto/PFSession.hpp"

#include "Bytes.hpp"   // internal/
#include "Limits.hpp"  // internal/
#include "Session.hpp" // internal/
#include "aead/record_crypto.hpp"

#include <utility>

namespace pf {

namespace {

Bytes *own(SecureBytes b) { return new Bytes(std::move(b)); }

} // namespace

BytesResult pf_seal(Session *s, const uint8_t *record_uuid, uint64_t version, uint16_t schema,
                    const uint8_t *plaintext, size_t pt_len) noexcept {
    try {
        if (s == nullptr || record_uuid == nullptr)
            return {nullptr, Status::BadInput};
        if ((plaintext == nullptr && pt_len != 0) || pt_len > kMaxSeamInput)
            return {nullptr, Status::BadInput};
        if (!s->alive())
            return {nullptr, Status::Locked};

        SecureBytes sealed = aead::seal(s->sub.k_record, s->vault_uuid.data(), record_uuid, version,
                                        schema, plaintext, pt_len);
        return {own(std::move(sealed)), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

BytesResult pf_open(Session *s, const uint8_t *record_uuid, uint64_t version, uint16_t schema,
                    const uint8_t *sealed, size_t sealed_len) noexcept {
    try {
        if (s == nullptr || record_uuid == nullptr)
            return {nullptr, Status::BadInput};
        if ((sealed == nullptr && sealed_len != 0) || sealed_len > kMaxSeamInput)
            return {nullptr, Status::BadInput};
        if (!s->alive())
            return {nullptr, Status::Locked};

        SecureBytes plaintext;
        const Status st = aead::open(s->sub.k_record, s->vault_uuid.data(), record_uuid, version,
                                     schema, sealed, sealed_len, plaintext);
        if (st != Status::Ok)
            return {nullptr, st};
        return {own(std::move(plaintext)), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

} // namespace pf
