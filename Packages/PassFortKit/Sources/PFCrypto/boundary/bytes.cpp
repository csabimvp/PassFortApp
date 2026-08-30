#include "PFCrypto/PFBytes.hpp"

#include <cstring>
#include <utility>
#include <vector>

#include "botan_all.h"

namespace pf {

// M0: a plain vector. M1 swaps this for Botan::secure_vector so wipe() is a real
// scrub (Botan::secure_scrub_memory), not a memset the optimizer may drop.
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

const uint8_t *pf_bytes_data(const Bytes *b) noexcept { return b ? b->data() : nullptr; }
size_t pf_bytes_size(const Bytes *b) noexcept { return b ? b->size() : 0; }

void pf_bytes_free(Bytes *b) noexcept {
    if (!b)
        return;
    b->wipe();
    delete b;
}

// Every boundary function: noexcept, catch-all -> Status. C++ exceptions
// terminate the process; Botan throws on the common path (architecture §6.1 rule 1).
BytesResult pf_echo(const uint8_t *data, size_t len) noexcept {
    try {
        if (data == nullptr && len != 0)
            return {nullptr, Status::BadInput};
        std::vector<uint8_t> copy;
        if (len != 0)
            copy.assign(data, data + len);
        return {new Bytes(std::move(copy)), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

BytesResult pf_botan_version() noexcept {
    try {
        const std::string v = Botan::version_string();
        return {new Bytes({v.begin(), v.end()}), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

} // namespace pf
