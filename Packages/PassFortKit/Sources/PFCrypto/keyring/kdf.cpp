// keyring/kdf.cpp -- see kdf.hpp.
#include "kdf.hpp"

#include "botan_all.h"

#include <algorithm>
#include <chrono>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace pf::keyring {

namespace {

constexpr uint32_t kMinKiB = 64u * 1024;    // 64 MiB floor (§5.2, a calibrate policy)
constexpr uint32_t kMaxKiB = kArgon2MaxKiB; // 4 GiB ceiling (§5.2)
constexpr uint32_t kFixedT = 3;
constexpr uint32_t kFixedP = 4;

// One Argon2id run at the given memory cost, wall-clock timed. Output length
// matches the real call (64 B) so the measurement reflects production cost.
uint64_t time_argon2id_ms(uint32_t m_kib) {
    auto fam = Botan::PasswordHashFamily::create_or_throw("Argon2id");
    auto ph = fam->from_params(m_kib, kFixedT, kFixedP);

    const std::string pw = "calibration-probe";
    const std::vector<uint8_t> salt(16, 0x00);
    std::vector<uint8_t> out(64);

    const auto start = std::chrono::steady_clock::now();
    ph->hash(out, pw, salt);
    const auto end = std::chrono::steady_clock::now();
    return static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count());
}

uint32_t clamp_kib(double v) {
    return static_cast<uint32_t>(
        std::clamp(v, static_cast<double>(kMinKiB), static_cast<double>(kMaxKiB)));
}

} // namespace

bool kdf_params_sane(const KdfParams &params) noexcept {
    if (params.kdf_id != 1)
        return false;
    if (params.t < 1 || params.t > kArgon2MaxCost)
        return false;
    if (params.p < 1 || params.p > kArgon2MaxCost)
        return false;
    if (params.m_kib > kArgon2MaxKiB)
        return false;
    if (params.m_kib < 8u * params.p) // Argon2's own minimum
        return false;
    return true;
}

SecureBytes argon2id_64(const uint8_t *pw, size_t pw_len, const KdfParams &params) {
    auto fam = Botan::PasswordHashFamily::create_or_throw("Argon2id");
    auto ph = fam->from_params(params.m_kib, params.t, params.p);

    SecureBytes out(64);
    ph->hash(out, std::string_view(reinterpret_cast<const char *>(pw), pw_len),
             std::span<const uint8_t>(params.salt, sizeof params.salt));
    return out;
}

// Argon2id runtime is close to linear in m for fixed t/p (the memory fill
// dominates), so a reference run at the floor extrapolates well; one refinement
// pass against the real cost at the estimate corrects the slope. Two runs, both
// bounded -- a full binary search over [64 MiB, 4 GiB] would run multi-GiB
// trials (runbook Phase 4 note; update the runbook if this shape stays).
KdfParams calibrate(uint32_t target_ms) {
    uint32_t m_kib = kMinKiB;

    const uint64_t ref_ms = time_argon2id_ms(kMinKiB);
    if (ref_ms > 0 && ref_ms < target_ms) {
        m_kib = clamp_kib(static_cast<double>(kMinKiB) *
                          (static_cast<double>(target_ms) / static_cast<double>(ref_ms)));

        const uint64_t measured_ms = time_argon2id_ms(m_kib);
        if (measured_ms > 0) {
            m_kib = clamp_kib(static_cast<double>(m_kib) *
                              (static_cast<double>(target_ms) / static_cast<double>(measured_ms)));
        }
    }

    KdfParams params;
    params.kdf_id = 1;
    params.m_kib = m_kib;
    params.t = kFixedT;
    params.p = kFixedP;
    Botan::system_rng().randomize(std::span<uint8_t>(params.salt, sizeof params.salt));
    return params;
}

} // namespace pf::keyring
