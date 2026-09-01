// aead/record_crypto.hpp -- per-record seal / open (§5.4). Internal to PFCrypto.
#pragma once

#include "PFCrypto/PFStatus.hpp" // pf::Status
#include "Secure.hpp"

#include <cstddef>
#include <cstdint>

namespace pf::aead {

// The AAD is assembled HERE and nowhere else, so its layout is defined once
// (§5.4):   aad = vault_uuid(16) , record_uuid(16) , version(u64 BE) , schema(u16 BE)
//
// seal:  plaintext -> nonce(24) , ciphertext , tag(16).
//        24 fresh random nonce bytes per call (§5.4 -- never a counter).
//        Throws Botan::Exception only on RNG / allocation failure.
SecureBytes seal(const SecureBytes &k_record, const uint8_t vault_uuid[16],
                 const uint8_t record_uuid[16], uint64_t version, uint16_t schema,
                 const uint8_t *plaintext, size_t pt_len);

// open:  nonce , ciphertext , tag -> plaintext_out.
//        wrong key / any wrong AAD component / tampered bytes -> Status::AuthFailed
//        sealed_len < 24 + 16                                 -> Status::BadInput
Status open(const SecureBytes &k_record, const uint8_t vault_uuid[16],
            const uint8_t record_uuid[16], uint64_t version, uint16_t schema, const uint8_t *sealed,
            size_t sealed_len, SecureBytes &plaintext_out);

} // namespace pf::aead
