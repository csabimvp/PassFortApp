// internal/Bytes.hpp -- shared, NOT exported (sibling of include/, not under it).
#pragma once
#include "PFCrypto/PFBytes.hpp" // pf::BytesResult, pf::Status
#include "Secure.hpp"           // SecureBytes

#include <cstddef>
#include <cstdint>
#include <utility>

namespace pf {

// The one owned-buffer type every boundary function returns, so keyring/aead/
// manifest can each hand back a single handle type.
//
// Backed by SecureBytes (Botan::secure_vector): ~Bytes scrubs the memory with
// Botan::secure_scrub_memory, which is written to be un-elidable -- so
// pf_bytes_free genuinely erases decrypted plaintext (pf_open returns it here),
// not a std::memset the optimizer is free to delete.
class Bytes {
public:
    explicit Bytes(SecureBytes bytes) : bytes_(std::move(bytes)) {}
    static Bytes copyOf(const uint8_t *p, size_t n) {
        return Bytes(n == 0 ? SecureBytes{} : SecureBytes(p, p + n));
    }

    const uint8_t *data() const noexcept { return bytes_.data(); }
    size_t size() const noexcept { return bytes_.size(); }

private:
    SecureBytes bytes_;
};

} // namespace pf
