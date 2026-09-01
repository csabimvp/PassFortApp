// internal/Bytes.hpp -- shared, NOT exported (sibling of include/, not under it).
#pragma once
#include "PFCrypto/PFBytes.hpp" // pf::BytesResult, pf::Status

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <utility>
#include <vector>

namespace pf {

// The one owned-buffer type every boundary function returns, so keyring/aead/
// manifest can each hand back a single handle type. Small enough to be header-only.
//
// M0: a plain vector. Phase 1 swaps the backing store for SecureBytes
// (Botan::secure_vector) so pf_bytes_free becomes a real scrub
// (Botan::secure_scrub_memory), not a memset the optimizer may drop.
class Bytes {
public:
    explicit Bytes(std::vector<uint8_t> bytes) : bytes_(std::move(bytes)) {}

    const uint8_t *data() const noexcept { return bytes_.data(); }
    size_t size() const noexcept { return bytes_.size(); }

    void wipe() noexcept {
        if (!bytes_.empty())
            std::memset(bytes_.data(), 0, bytes_.size());
    }

private:
    std::vector<uint8_t> bytes_;
};

} // namespace pf
