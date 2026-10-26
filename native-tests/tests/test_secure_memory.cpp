#include "internal/Secure.hpp"
#include <catch2/catch_test_macros.hpp>
#include <cstdint>
#include <sys/resource.h>

#if defined(__APPLE__)
#include <libproc.h>
#include <unistd.h>
#else
#include <fstream>
#include <string>
#endif

namespace {

/// Bytes of this process's memory that mlock() holds: the wired size on macOS, `VmLck` on Linux.
uint64_t locked_bytes() {
#if defined(__APPLE__)
    rusage_info_v4 usage{};
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_V4, reinterpret_cast<rusage_info_t *>(&usage)) != 0)
        return 0;
    return usage.ri_wired_size;
#else
    std::ifstream status("/proc/self/status");
    for (std::string line; std::getline(status, line);) {
        if (line.rfind("VmLck:", 0) == 0)
            return std::stoull(line.substr(6)) * 1024; // "VmLck:     512 kB"
    }
    return 0;
#endif
}

bool address_sanitizer() {
#if defined(__SANITIZE_ADDRESS__)
    return true;
#elif defined(__has_feature)
#if __has_feature(address_sanitizer)
    return true;
#else
    return false;
#endif
#else
    return false;
#endif
}

} // namespace

// Regression: until 2026-10-26 the amalgamation had no locking_allocator, so no key was ever
// mlock()ed despite architecture.md §3.4. Botan locks its pool when the allocator first starts,
// up to 512 KiB, capped by RLIMIT_MEMLOCK (whose soft limit it raises to the hard limit).
TEST_CASE("secure_vector memory is mlock()ed when the limit allows it", "[secure]") {
    if (address_sanitizer())
        SKIP("AddressSanitizer turns mlock() into a no-op");
    rlimit limit{};
    REQUIRE(getrlimit(RLIMIT_MEMLOCK, &limit) == 0);
    if (limit.rlim_max == 0)
        SKIP("RLIMIT_MEMLOCK is 0: Botan falls back to unlocked memory by design");

    pf::SecureBytes key(32, 0x5A);
    CHECK(locked_bytes() > 0);
}
