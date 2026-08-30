#pragma once
#include <cstddef>
#include <cstdint>
#include "PFStatus.hpp"

namespace pf
{

    // Opaque -- Swift sees a pointer it can only touch through these functions.
    // Defined in boundary/bytes.cpp (architecture §6.1 rule 3).
    class Bytes;

    struct BytesResult
    {
        Bytes *handle;
        Status status;
    };

    const uint8_t *pf_bytes_data(const Bytes *b) noexcept;
    size_t pf_bytes_size(const Bytes *b) noexcept;
    void pf_bytes_free(Bytes *b) noexcept; // zeroizes, then frees

    // M0 probe: copies [data, data+len) into a fresh handle. Proves the whole
    // §6.3 round-trip. Deleted once real seal/open exists.
    BytesResult pf_echo(const uint8_t *data, size_t len) noexcept;

    // Phase 3 link probe: returns Botan::version_string() as bytes. Deleted at M1.
    BytesResult pf_botan_version() noexcept;

} // namespace pf
