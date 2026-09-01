// keyring/hkdf.cpp -- see hkdf.hpp.
#include "hkdf.hpp"

#include "botan_all.h"

#include <cstdint>
#include <span>

namespace pf::keyring {

namespace {

// HKDF-Expand only. Botan's "HKDF-Expand(SHA-256)" folds `label , salt` as the
// info input; we pass the label and leave salt empty, so info is exactly the
// label -- byte-identical to a standard HKDF-Expand(PRK, info, 32) in Swift or
// WASM, which is what keeps one vault format openable by three hosts.
SecureBytes expand(const SecureBytes &key, std::string_view info) {
    auto kdf = Botan::KDF::create_or_throw("HKDF-Expand(SHA-256)");
    return kdf->derive_key<SecureBytes>(
        32, std::span<const uint8_t>(key), std::span<const uint8_t>{},
        std::span<const uint8_t>(reinterpret_cast<const uint8_t *>(info.data()), info.size()));
}

} // namespace

RootKeys derive_root(const SecureBytes &argon64) {
    return {
        .kek = expand(argon64, kInfoKek),
        .auth_secret = expand(argon64, kInfoAuth),
    };
}

DekSubkeys derive_dek_subkeys(const SecureBytes &dek) {
    return {
        .k_record = expand(dek, kInfoRecord),
        .k_index = expand(dek, kInfoIndex),
        .k_manifest = expand(dek, kInfoManifest),
    };
}

} // namespace pf::keyring
