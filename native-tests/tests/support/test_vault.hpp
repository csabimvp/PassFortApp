// Shared test helpers: build a vault header, open a session, drain a BytesResult.
#pragma once

#include <catch2/catch_test_macros.hpp>

#include "PFCrypto/PFSession.hpp"

#include <cstdint>
#include <cstring>
#include <vector>

namespace pf_test {

// Cheap Argon2 -- these suites are not KAT'ing the KDF. m_kib defaults to 8 MiB;
// pass a tiny value (e.g. 16) for loops that open a header many times.
inline pf::KdfParams fast_kdf(uint32_t m_kib = 8u * 1024) {
    pf::KdfParams p{};
    p.kdf_id = 1;
    p.m_kib = m_kib;
    p.t = 1;
    p.p = 1;
    std::memset(p.salt, 0x2b, sizeof p.salt);
    return p;
}

inline std::vector<uint8_t> make_header(const std::vector<uint8_t> &password,
                                        pf::KdfParams kdf = fast_kdf()) {
    auto created = pf::pf_vault_create(password.data(), password.size(), kdf);
    REQUIRE(created.status == pf::Status::Ok);
    std::vector<uint8_t> h(pf::pf_bytes_data(created.handle),
                           pf::pf_bytes_data(created.handle) + pf::pf_bytes_size(created.handle));
    pf::pf_bytes_free(created.handle);
    return h;
}

// Owns a live session for the duration of a test body.
struct Vault {
    pf::Session *session = nullptr;

    explicit Vault(const std::vector<uint8_t> &password = {'p', 'w'},
                   pf::KdfParams kdf = fast_kdf()) {
        const auto header = make_header(password, kdf);
        auto opened =
            pf::pf_session_open(header.data(), header.size(), password.data(), password.size());
        REQUIRE(opened.status == pf::Status::Ok);
        session = opened.handle;
    }
    ~Vault() { pf::pf_session_close(session); }
    Vault(const Vault &) = delete;
    Vault &operator=(const Vault &) = delete;
};

// Copy out the bytes and free the handle. REQUIREs Ok.
inline std::vector<uint8_t> bytes_of(pf::BytesResult r) {
    REQUIRE(r.status == pf::Status::Ok);
    std::vector<uint8_t> out(pf::pf_bytes_data(r.handle),
                             pf::pf_bytes_data(r.handle) + pf::pf_bytes_size(r.handle));
    pf::pf_bytes_free(r.handle);
    return out;
}

// Free any returned handle, return only the status.
inline pf::Status drain(pf::BytesResult r) {
    if (r.handle != nullptr)
        pf::pf_bytes_free(r.handle);
    return r.status;
}

} // namespace pf_test
