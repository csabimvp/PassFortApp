#include <catch2/catch_test_macros.hpp>

#include "PFCrypto/PFManifest.hpp"
#include "PFCrypto/PFSession.hpp"
#include "botan_all.h"
#include "manifest/manifest_mac.hpp"

#include <array>
#include <cstring>
#include <vector>

namespace {

pf::KdfParams fast_kdf() {
    pf::KdfParams p{};
    p.kdf_id = 1;
    p.m_kib = 8 * 1024;
    p.t = 1;
    p.p = 1;
    std::memset(p.salt, 0x2b, sizeof p.salt);
    return p;
}

struct TestVault {
    pf::Session *session = nullptr;
    TestVault() {
        const std::vector<uint8_t> pw{'p', 'w'};
        auto created = pf::pf_vault_create(pw.data(), pw.size(), fast_kdf());
        REQUIRE(created.status == pf::Status::Ok);
        const std::vector<uint8_t> header(pf::pf_bytes_data(created.handle),
                                          pf::pf_bytes_data(created.handle) +
                                              pf::pf_bytes_size(created.handle));
        pf::pf_bytes_free(created.handle);
        auto opened = pf::pf_session_open(header.data(), header.size(), pw.data(), pw.size());
        REQUIRE(opened.status == pf::Status::Ok);
        session = opened.handle;
    }
    ~TestVault() { pf::pf_session_close(session); }
};

struct Row {
    std::array<uint8_t, 16> uuid;
    uint64_t version;
    std::vector<uint8_t> sealed;
};

std::vector<uint8_t> mac_of(pf::Session *s, uint64_t vault_version, const std::vector<Row> &rows) {
    auto init = pf::pf_mac_init(s, vault_version);
    REQUIRE(init.status == pf::Status::Ok);
    for (const auto &r : rows) {
        REQUIRE(pf::pf_mac_update(init.handle, r.uuid.data(), r.version, r.sealed.data(),
                                  r.sealed.size()) == pf::Status::Ok);
    }
    auto fin = pf::pf_mac_finish(init.handle);
    REQUIRE(fin.status == pf::Status::Ok);
    std::vector<uint8_t> out(pf::pf_bytes_data(fin.handle),
                             pf::pf_bytes_data(fin.handle) + pf::pf_bytes_size(fin.handle));
    pf::pf_bytes_free(fin.handle);
    pf::pf_mac_free(init.handle);
    return out;
}

Row make_row(uint8_t uuid_byte, uint64_t version, uint8_t sealed_byte, size_t sealed_len) {
    Row r;
    r.uuid.fill(uuid_byte);
    r.version = version;
    r.sealed.assign(sealed_len, sealed_byte);
    return r;
}

} // namespace

TEST_CASE("manifest MAC is 32 bytes and deterministic for the same rows", "[manifest]") {
    TestVault v;
    const std::vector<Row> rows{make_row(0x11, 1, 0xaa, 48), make_row(0x22, 3, 0xbb, 80),
                                make_row(0x33, 1, 0xcc, 41)};

    const auto a = mac_of(v.session, 1, rows);
    REQUIRE(a.size() == 32);
    REQUIRE(a == mac_of(v.session, 1, rows));
}

TEST_CASE("manifest MAC depends on row order, row set, and vault_version", "[manifest]") {
    TestVault v;
    const std::vector<Row> rows{make_row(0x11, 1, 0xaa, 48), make_row(0x22, 3, 0xbb, 80),
                                make_row(0x33, 1, 0xcc, 41)};
    const auto base = mac_of(v.session, 1, rows);

    std::vector<Row> reordered{rows[1], rows[0], rows[2]};
    REQUIRE(mac_of(v.session, 1, reordered) != base); // ordering is the caller's job

    std::vector<Row> dropped{rows[0], rows[2]};
    REQUIRE(mac_of(v.session, 1, dropped) != base); // deletion is detectable

    REQUIRE(mac_of(v.session, 2, rows) != base); // whole-file rollback is detectable
}

TEST_CASE("manifest MAC changes if a single sealed byte changes", "[manifest]") {
    TestVault v;
    std::vector<Row> rows{make_row(0x11, 1, 0xaa, 48), make_row(0x22, 3, 0xbb, 80)};
    const auto base = mac_of(v.session, 1, rows);

    rows[0].sealed[10] ^= 0x01;
    REQUIRE(mac_of(v.session, 1, rows) != base);
}

TEST_CASE("manifest MAC is bound to k_manifest (different vault -> different MAC)", "[manifest]") {
    TestVault a;
    TestVault b;
    const std::vector<Row> rows{make_row(0x11, 1, 0xaa, 48)};
    REQUIRE(mac_of(a.session, 1, rows) != mac_of(b.session, 1, rows));
}

TEST_CASE("pf_mac_update after pf_mac_finish returns BadInput", "[manifest]") {
    TestVault v;
    auto init = pf::pf_mac_init(v.session, 1);
    REQUIRE(init.status == pf::Status::Ok);

    const std::array<uint8_t, 16> uuid{0x11};
    const std::vector<uint8_t> sealed(48, 0x01);
    REQUIRE(pf::pf_mac_update(init.handle, uuid.data(), 1, sealed.data(), sealed.size()) ==
            pf::Status::Ok);

    auto fin = pf::pf_mac_finish(init.handle);
    REQUIRE(fin.status == pf::Status::Ok);
    pf::pf_bytes_free(fin.handle);

    REQUIRE(pf::pf_mac_update(init.handle, uuid.data(), 2, sealed.data(), sealed.size()) ==
            pf::Status::BadInput);
    REQUIRE(pf::pf_mac_finish(init.handle).status == pf::Status::BadInput); // single-shot

    pf::pf_mac_free(init.handle);
}

TEST_CASE("an empty vault still has a manifest MAC", "[manifest]") {
    TestVault v;
    REQUIRE(mac_of(v.session, 1, {}).size() == 32);
}

// Frozen vector: k_manifest, vault_version and two rows are fixed, and the MAC
// is cross-checked against an independent HMAC-SHA-256 (Python). If the layout
// (label order, u64 endianness, "SHA-256(sealed)" step) ever drifts, this
// breaks -- it is on-disk format (§5.5). A Swift/WASM port must reproduce it.
TEST_CASE("manifest MAC matches an independent HMAC-SHA-256 (format regression)", "[manifest]") {
    const pf::SecureBytes k_manifest(32, 0x4d);
    pf::manifest::ManifestMac m(k_manifest, /*vault_version=*/7);

    std::array<uint8_t, 16> uuid_a{};
    uuid_a.fill(0xa1);
    std::array<uint8_t, 16> uuid_b{};
    uuid_b.fill(0xb2);
    const std::vector<uint8_t> sealed_a(48, 0x11);
    const std::vector<uint8_t> sealed_b(80, 0x22);

    REQUIRE(m.update(uuid_a.data(), 1, sealed_a.data(), sealed_a.size()) == pf::Status::Ok);
    REQUIRE(m.update(uuid_b.data(), 2, sealed_b.data(), sealed_b.size()) == pf::Status::Ok);
    const auto mac = m.finish();

    // Python: hmac_sha256(0x4d*32,
    //   be64(7) , 0xa1*16,be64(1),sha256(0x11*48) , 0xb2*16,be64(2),sha256(0x22*80))
    REQUIRE(Botan::hex_encode(mac, /*uppercase=*/false) ==
            "2044ca7973d7fdb0273ac5bab38fc338fc3a2f9e5dbb1dd0b24da54980eeb4e1");
}
