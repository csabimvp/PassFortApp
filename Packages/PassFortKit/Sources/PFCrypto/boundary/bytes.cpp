#include "PFCrypto/PFBytes.hpp"

#include <string>

#include "Bytes.hpp"
#include "Limits.hpp"
#include "Secure.hpp"
#include "botan_all.h"

namespace pf {

const uint8_t *pf_bytes_data(const Bytes *b) noexcept { return b ? b->data() : nullptr; }
size_t pf_bytes_size(const Bytes *b) noexcept { return b ? b->size() : 0; }

void pf_bytes_free(Bytes *b) noexcept {
    delete b; // ~Bytes -> ~SecureBytes scrubs the buffer (Bytes.hpp)
}

// Every boundary function: noexcept, catch-all -> Status. C++ exceptions
// terminate the process; Botan throws on the common path (architecture §6.1 rule 1).
BytesResult pf_echo(const uint8_t *data, size_t len) noexcept {
    try {
        if ((data == nullptr && len != 0) || len > kMaxSeamInput)
            return {nullptr, Status::BadInput};
        return {new Bytes(Bytes::copyOf(data, len)), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

BytesResult pf_botan_version() noexcept {
    try {
        const std::string v = Botan::version_string();
        return {new Bytes(SecureBytes(v.begin(), v.end())), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

} // namespace pf
