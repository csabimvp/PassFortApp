# PassFort — Build bootstrap runbook

**Status:** Active. Follow top to bottom to go from an empty repo to a building SwiftPM package with the
Swift↔C++ seam proven end to end (milestone M0), plus the Botan, CMake, and CI scaffolding M1 needs.
**Last updated:** 2026-08-30 (Phase 1: add the GitHub remote and reconcile with its README commit)

This runbook implements the "Immediate next steps" of `architecture.md` §15. Once the commands here are
real and stable, fold them into the README's *Getting started* / *Testing* sections and retire this file
to a historical note.

---

## How the three build systems relate

| Build system | Role | When |
|---|---|---|
| **SwiftPM** (`Package.swift`) | The real build system. Compiles `PFCrypto` (C++), `PassFortCrypto`, `PassFortVault`, `passfort-cli`. The daily `swift build` / `swift test` loop. | Now (M0) and onward |
| **CMake** | Builds `native-tests/` only — Catch2 unit tests over `PFCrypto`'s C++ internals, run outside Xcode. Never touches the app build graph. | Phase 4 |
| **Xcode project** | A thin shell: a macOS app target consuming the SwiftPM package as a local dependency. Added when the GUI starts. | M3 (Phase 6) |

CI (GitHub Actions, Phase 5) orchestrates the first two — it does not add a build system, it runs
`swift test` and `ctest` on a clean machine on every push.

Botan is built by its own `configure.py` (Python, not CMake) into a two-file amalgamation that is
committed to the repo (ADR-0001). There is no CMake-generated Xcode project. CMake here is a small
side-channel test harness.

Milestones M1 and M2 are built entirely through `passfort-cli` (`architecture.md` §12), so this runbook
stops once the seam is proven and the M1 scaffolding is in place.

---

## Phase 0 — Toolchain

```bash
# architecture.md §4.1: xcode-select points at CommandLineTools, so xcodebuild won't run.
sudo xcode-select -s /Applications/Xcode.app

# Verify against architecture.md §4.1
xcode-select -p                 # -> /Applications/Xcode.app/Contents/Developer
xcodebuild -version             # -> Xcode 26.6
swift --version                 # -> 6.3.x
clang --version                 # -> 21.x

# Dev-time only (not shipped): Botan reference build + CMake for native tests
brew install botan cmake
botan version                   # -> 3.12.0
cmake --version                 # -> 4.4.x
```

**Checkpoint:** all five versions match §4.1. If Homebrew's Botan is not 3.12.0 it does not matter — the
vendored amalgamation (Phase 3) is what ships; Homebrew's copy is only for experiments.

---

## Phase 1 — Repo skeleton and git

```bash
cd /Users/csabimvp/dev/projects/PassFortApp

mkdir -p \
  Packages/PassFortKit/Sources/PFCrypto/include/PFCrypto \
  Packages/PassFortKit/Sources/PFCrypto/boundary \
  Packages/PassFortKit/Sources/PFCrypto/vendor/botan \
  Packages/PassFortKit/Sources/PassFortCrypto \
  Packages/PassFortKit/Sources/PassFortVault \
  Packages/PassFortKit/Sources/passfort-cli \
  Packages/PassFortKit/Tests/PFCryptoBoundaryTests \
  native-tests/tests \
  scripts
```

`.gitignore` at the repo root — from `architecture.md` §15 step 2:

```gitignore
# Swift / Xcode
.build/
.swiftpm/
DerivedData/
*.xcuserstate
xcuserdata/
.DS_Store

# CMake — out-of-source build dir, disposable
native-tests/build/

# Vault data — never commit anything with real secrets
*.pfvault
*.sqlite
*.sqlite-wal
*.sqlite-shm

# Later milestones (Cloud/, Web/)
node_modules/
*.wasm
.azure/
Cloud/api/local.settings.json
```

The Botan amalgamation under `vendor/botan/` **is** committed (ADR-0001) — do not ignore it.

```bash
git init
git add .gitignore docs
git commit -m "Add architecture docs and repo scaffold

Design artefacts are complete (architecture.md rev 4, ADR-0001..0006);
this starts the build phase per architecture.md §15."
```

**Checkpoint:** `git status` is clean apart from the still-empty source directories (git does not track
empty directories — expected).

The `git-and-commits.md` convention mentions a staged-diff secret-scan hook. If it is not installed yet
that is fine for now; it must be enforcing before the first M5 commit that touches
`Cloud/api/local.settings.json`.

### Add the GitHub remote

The GitHub repo — `git@github.com:csabimvp/PassFortApp.git` — was created through the web UI with a
README, so `origin/main` already carries one commit that the local repo does not. The two histories are
independent roots. Don't force-push over GitHub's commit; replay the local history on top of it:

```bash
cd /Users/csabimvp/dev/projects/PassFortApp

git remote add origin git@github.com:csabimvp/PassFortApp.git
git fetch origin

# Rebase the local scaffold commit(s) onto GitHub's initial README commit. Rebase
# does not need --allow-unrelated-histories (that flag is merge/pull only); it just
# replays every local commit that origin/main lacks.
git rebase origin/main

git log --oneline --graph        # -> README commit is the root, local commits follow
```

No conflict is expected: there is no `README.md` in the local tree yet, so GitHub's commit and the local
scaffold commit touch disjoint files. If git *does* stop, the conflict is in `README.md` — reconcile it
(the header note about folding the command loops into the README applies to this file), then
`git add README.md && git rebase --continue`.

Pushing needs an explicit ask every time (`git-and-commits.md`), so it does not happen here. The first
push is at the end of Phase 5, once CI and formatting are in place:

```bash
git push -u origin main
```

**Checkpoint:** `git log --oneline` shows the GitHub README commit followed by the local scaffold
commit(s), and `git status` reports `Your branch is ahead of 'origin/main' by N commits`.

---

## Phase 2 — SwiftPM package and the M0 seam

This phase proves the §6.3 marshaling pattern in the repo and that the §4 layering is enforced by the
compiler rather than by review.

### `Packages/PassFortKit/Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PassFortKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PassFortVault", targets: ["PassFortVault"]),
        .executable(name: "passfort-cli", targets: ["passfort-cli"]),
    ],
    targets: [
        // -- C++ -- keys and byte-marshaling only. NO interop flag on this target. --
        .target(
            name: "PFCrypto",
            cxxSettings: [
                .headerSearchPath("include"),
                // Phase 3 adds: .headerSearchPath("vendor/botan"),
            ]
        ),

        // -- The ONLY module compiled with C++ interop (architecture §4). --
        .target(
            name: "PassFortCrypto",
            dependencies: ["PFCrypto"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),

        // -- Swift storage/model/sync. MUST NOT import PFCrypto -- no interop flag,
        //    so a layering violation is a compile error, not a review catch. --
        .target(
            name: "PassFortVault",
            dependencies: ["PassFortCrypto"]
            // GRDB added at M2 (architecture §8)
        ),

        .executableTarget(
            name: "passfort-cli",
            dependencies: ["PassFortVault", "PassFortCrypto"]
        ),

        // The one sanctioned interop exception besides PassFortCrypto: the boundary
        // fuzz suite (architecture §13) needs to call pf_* directly.
        .testTarget(
            name: "PFCryptoBoundaryTests",
            dependencies: ["PassFortCrypto", "PFCrypto"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ],
    cxxLanguageStandard: .cxx20
)
```

### `Packages/PassFortKit/Sources/PFCrypto/include/module.modulemap`

```
module PFCrypto {
    umbrella "PFCrypto"
    export *
    requires cplusplus
}
```

### `Packages/PassFortKit/Sources/PFCrypto/include/PFCrypto/PFStatus.hpp`

```cpp
#pragma once
#include <cstdint>

namespace pf {

// Plain enum, fixed width -- crosses the seam as an int32. Translated to a Swift
// error by PassFortCrypto. A wrong password and a corrupt record BOTH map to
// AuthFailed so the API is not a decryption oracle (architecture §13, ADR-0002).
enum class Status : int32_t {
    Ok = 0, BadInput = 1, Locked = 2, AuthFailed = 3,
    NotFound = 4, Unsupported = 5, Internal = 99
};

}  // namespace pf
```

### `Packages/PassFortKit/Sources/PFCrypto/include/PFCrypto/PFBytes.hpp`

```cpp
#pragma once
#include <cstddef>
#include <cstdint>
#include "PFStatus.hpp"

namespace pf {

// Opaque -- Swift sees a pointer it can only touch through these functions.
// Defined in boundary/bytes.cpp (architecture §6.1 rule 3).
class Bytes;

struct BytesResult {
    Bytes* handle;
    Status status;
};

const uint8_t* pf_bytes_data(const Bytes* b) noexcept;
size_t         pf_bytes_size(const Bytes* b) noexcept;
void           pf_bytes_free(Bytes* b) noexcept;   // zeroizes, then frees

// M0 probe: copies [data, data+len) into a fresh handle. Proves the whole
// §6.3 round-trip. Deleted once real seal/open exists.
BytesResult    pf_echo(const uint8_t* data, size_t len) noexcept;

}  // namespace pf
```

### `Packages/PassFortKit/Sources/PFCrypto/boundary/bytes.cpp`

```cpp
#include "PFCrypto/PFBytes.hpp"

#include <cstring>
#include <utility>
#include <vector>

namespace pf {

// M0: a plain vector. M1 swaps this for Botan::secure_vector so wipe() is a real
// scrub (Botan::secure_scrub_memory), not a memset the optimizer may drop.
class Bytes {
public:
    explicit Bytes(std::vector<uint8_t> bytes) : bytes_(std::move(bytes)) {}

    const uint8_t* data() const noexcept { return bytes_.data(); }
    size_t size() const noexcept { return bytes_.size(); }

    void wipe() noexcept {
        if (!bytes_.empty()) std::memset(bytes_.data(), 0, bytes_.size());
    }

private:
    std::vector<uint8_t> bytes_;
};

const uint8_t* pf_bytes_data(const Bytes* b) noexcept { return b ? b->data() : nullptr; }
size_t         pf_bytes_size(const Bytes* b) noexcept { return b ? b->size() : 0; }

void pf_bytes_free(Bytes* b) noexcept {
    if (!b) return;
    b->wipe();
    delete b;
}

// Every boundary function: noexcept, catch-all -> Status. C++ exceptions
// terminate the process; Botan throws on the common path (architecture §6.1 rule 1).
BytesResult pf_echo(const uint8_t* data, size_t len) noexcept {
    try {
        if (data == nullptr && len != 0) return {nullptr, Status::BadInput};
        std::vector<uint8_t> copy;
        if (len != 0) copy.assign(data, data + len);
        return {new Bytes(std::move(copy)), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}

}  // namespace pf
```

### `Packages/PassFortKit/Sources/PassFortCrypto/PassFortError.swift`

```swift
internal import PFCrypto   // `internal` keeps pf.* out of this module's public API,
                           // which is what stops interop mode going viral downstream.

/// Swift-side view of a `pf::Status`. Deliberately carries no C++ type.
public enum PassFortError: Error, Equatable {
    case badInput, locked, authFailed, notFound, unsupported, unexpected

    init(_ status: pf.Status) {
        switch status {
        case .BadInput:    self = .badInput
        case .Locked:      self = .locked
        case .AuthFailed:  self = .authFailed
        case .NotFound:    self = .notFound
        case .Unsupported: self = .unsupported
        default:           self = .unexpected
        }
    }
}
```

### `Packages/PassFortKit/Sources/PassFortCrypto/Seam.swift`

```swift
import Foundation
internal import PFCrypto

/// The single place `pf::BytesResult` -> `Data` marshaling lives (architecture §6.3).
func consume(_ r: pf.BytesResult) throws -> Data {
    guard r.status == pf.Status.Ok, let handle = r.handle else {
        throw PassFortError(r.status)
    }
    defer { pf.pf_bytes_free(handle) }
    guard let base = pf.pf_bytes_data(handle) else { return Data() }
    return Data(bytes: base, count: pf.pf_bytes_size(handle))
}

/// M0 smoke test of the seam: bytes in, identical bytes out, via a C++ round trip.
public func echo(_ input: Data) throws -> Data {
    try input.withUnsafeBytes { raw in
        try consume(pf.pf_echo(raw.bindMemory(to: UInt8.self).baseAddress, raw.count))
    }
}
```

### `Packages/PassFortKit/Sources/PassFortVault/Vault.swift`

```swift
import Foundation
import PassFortCrypto

// Uncomment the next line, run `swift build`, and it fails to compile.
// That failure IS the §4 layering guarantee -- PassFortVault cannot see PFCrypto.
// import PFCrypto

public enum Vault {
    /// Proves the allowed direction: PassFortVault -> PassFortCrypto (pure Swift API).
    public static func seamSelfTest(_ probe: Data) throws -> Data {
        try echo(probe)
    }
}
```

### `Packages/PassFortKit/Sources/passfort-cli/main.swift`

```swift
import Foundation
import PassFortCrypto

let probe = Data("passfort seam check".utf8)
guard try echo(probe) == probe else {
    FileHandle.standardError.write(Data("seam round-trip MISMATCH\n".utf8))
    exit(1)
}
print("seam OK -- \(probe.count) bytes round-tripped through C++")
```

### `Packages/PassFortKit/Tests/PFCryptoBoundaryTests/BoundaryTests.swift`

```swift
import Testing
import Foundation
@testable import PassFortCrypto

@Suite struct BoundaryTests {
    @Test func echoRoundTripsArbitraryBytes() throws {
        let input = Data((0..<512).map { UInt8($0 & 0xFF) })
        #expect(try echo(input) == input)
    }

    @Test func echoHandlesEmptyInput() throws {
        #expect(try echo(Data()) == Data())
    }
}
```

### Build and test

```bash
cd Packages/PassFortKit
swift build
swift test
swift run passfort-cli
```

**Checkpoint (M0 done):** `swift test` is green and `passfort-cli` prints `seam OK`. The §6.3 pattern is
proven in the repo, not in a scratch package.

**If `swift build` reports that `PassFortVault` needs `.interoperabilityMode(.Cxx)`:** that is the C++
interop transitivity limitation. The fix is not to add the flag — it is to confirm that no `pf.*` type
appears in any `public` or `package` declaration of `PassFortCrypto`. The `internal import` plus the
plain-enum `PassFortError` are designed to prevent exactly this leak.

---

## Phase 3 — Botan amalgamation

### `scripts/build_botan.sh`

```bash
#!/usr/bin/env bash
# Regenerate the vendored Botan amalgamation. Run deliberately, NEVER from the
# build graph (ADR-0001). Requires: git, python3, clang.
set -euo pipefail

BOTAN_VERSION="3.12.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/Packages/PassFortKit/Sources/PFCrypto/vendor/botan"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# Module set from ADR-0001. `./configure.py --list-modules` is the authority on
# exact names if any are rejected. Adjust --cpu to x86_64 on an Intel Mac.
MODULES="argon2,argon2fmt,chacha20poly1305,chacha,poly1305,aes,aes_armv8,gcm,\
hmac,sha2_32,sha2_64,hkdf,pbkdf2,auto_rng,system_rng,hmac_drbg,\
base64,base32,hex,rfc3394"

echo "Cloning Botan ${BOTAN_VERSION}..."
git clone --depth 1 --branch "${BOTAN_VERSION}" \
  https://github.com/randombit/botan.git "${WORK_DIR}/botan"

cd "${WORK_DIR}/botan"
python3 ./configure.py \
  --amalgamation \
  --minimized-build \
  --enable-modules="${MODULES}" \
  --disable-shared-library \
  --without-documentation \
  --cc=clang --os=macos --cpu=arm64

mkdir -p "${VENDOR_DIR}"
cp botan_all.h botan_all.cpp "${VENDOR_DIR}/"
cp license.txt "${VENDOR_DIR}/" 2>/dev/null || true
printf 'Botan %s\nModules: %s\n' "${BOTAN_VERSION}" "${MODULES}" \
  > "${VENDOR_DIR}/AMALGAMATION_INFO.txt"

echo "Wrote amalgamation -> ${VENDOR_DIR}"
```

```bash
chmod +x scripts/build_botan.sh
./scripts/build_botan.sh
ls Packages/PassFortKit/Sources/PFCrypto/vendor/botan/   # botan_all.h  botan_all.cpp  ...
```

### Wire Botan into `PFCrypto`

In `Package.swift`, uncomment the second header search path:

```swift
.target(
    name: "PFCrypto",
    cxxSettings: [
        .headerSearchPath("include"),
        .headerSearchPath("vendor/botan"),
    ]
),
```

`botan_all.cpp` lives under `Sources/PFCrypto/`, so SwiftPM compiles it into the target automatically.
Its headers stay out of `include/`, so the Swift compiler never parses them — the point of §4.

### Prove the link

Add to `boundary/bytes.cpp`, inside `namespace pf` (and add `#include "botan_all.h"` near the top):

```cpp
BytesResult pf_botan_version() noexcept {
    try {
        const std::string v = Botan::version_string();
        return {new Bytes({v.begin(), v.end()}), Status::Ok};
    } catch (...) {
        return {nullptr, Status::Internal};
    }
}
```

Declare `BytesResult pf_botan_version() noexcept;` in `PFBytes.hpp`. Then in
`PassFortCrypto/Seam.swift`:

```swift
public func botanVersion() throws -> String {
    String(decoding: try consume(pf.pf_botan_version()), as: UTF8.self)
}
```

Add `print("botan \(try botanVersion())")` to `passfort-cli/main.swift`.

```bash
swift build       # SLOW first time -- botan_all.cpp is one large TU. Incremental builds are instant.
swift run passfort-cli
```

**Checkpoint:** the CLI prints `botan 3.12.0`. Botan is vendored, linked, and invisible to Swift. Commit
the amalgamation and `build_botan.sh` together.

The amalgamation bakes in this machine's target arch (`aes_armv8`, endianness). ADR-0001's "pin the
version, re-run deliberately" applies per target arch — revisit if iOS or an Intel target ever appears.

---

## Phase 4 — CMake native tests

**The CMake model, briefly.** `CMakeLists.txt` describes targets abstractly. `cmake -S <src> -B <build>`
*configures*: reads that file, finds the compiler, fetches dependencies, writes real build files into
`<build>`. `cmake --build <build>` *compiles*. `ctest --test-dir <build>` runs the tests. `<build>` is
disposable and gitignored. Re-run configure only after editing `CMakeLists.txt`; after editing code,
just re-run `--build`.

### `native-tests/CMakeLists.txt`

```cmake
cmake_minimum_required(VERSION 3.28)
project(passfort_native_tests CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Catch2 v3 -- cloned and built on first configure.
include(FetchContent)
FetchContent_Declare(Catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    GIT_TAG        v3.7.1)
FetchContent_MakeAvailable(Catch2)

set(PFCRYPTO ${CMAKE_CURRENT_SOURCE_DIR}/../Packages/PassFortKit/Sources/PFCrypto)

# Botan as its own static lib: warnings stay contained, and it only recompiles
# when the amalgamation itself changes.
add_library(pf_botan STATIC ${PFCRYPTO}/vendor/botan/botan_all.cpp)
target_include_directories(pf_botan PUBLIC ${PFCRYPTO}/vendor/botan)
target_compile_options(pf_botan PRIVATE -w)          # vendored -- not ours to lint

add_executable(pfcrypto_tests
    ${PFCRYPTO}/boundary/bytes.cpp
    tests/test_bytes.cpp)
target_include_directories(pfcrypto_tests PRIVATE ${PFCRYPTO}/include)
target_compile_options(pfcrypto_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(pfcrypto_tests PRIVATE pf_botan Catch2::Catch2WithMain)

enable_testing()
include(Catch)
catch_discover_tests(pfcrypto_tests)
```

`-Wall -Wextra -Wpedantic -Werror` on our code is the `cpp.md` rule; Botan gets `-w`.

### `native-tests/tests/test_bytes.cpp`

```cpp
#include <catch2/catch_test_macros.hpp>
#include "PFCrypto/PFBytes.hpp"
#include <cstdint>
#include <vector>

TEST_CASE("pf_echo round-trips bytes through an opaque handle", "[boundary]") {
    const std::vector<uint8_t> input{1, 2, 3, 4, 5};
    auto r = pf::pf_echo(input.data(), input.size());

    REQUIRE(r.status == pf::Status::Ok);
    REQUIRE(r.handle != nullptr);
    REQUIRE(pf::pf_bytes_size(r.handle) == input.size());

    const uint8_t* out = pf::pf_bytes_data(r.handle);
    REQUIRE(std::vector<uint8_t>(out, out + input.size()) == input);

    pf::pf_bytes_free(r.handle);
}

TEST_CASE("pf_echo rejects null pointer with non-zero length", "[boundary]") {
    auto r = pf::pf_echo(nullptr, 8);
    REQUIRE(r.status == pf::Status::BadInput);
    REQUIRE(r.handle == nullptr);
}
```

### Run it

```bash
cd /Users/csabimvp/dev/projects/PassFortApp
cmake -S native-tests -B native-tests/build      # configure (slow: fetches + builds Catch2 + Botan)
cmake --build native-tests/build                 # compile
ctest --test-dir native-tests/build --output-on-failure
```

**Checkpoint:** two tests pass. From here, iterate with
`cmake --build native-tests/build && ctest --test-dir native-tests/build`. The RFC known-answer tests
and boundary fuzzing (`architecture.md` §13) will live here.

---

## Phase 5 — Continuous integration

A minimal GitHub Actions pipeline running the M1 job set from `architecture.md` §13.2 — `swift`,
`native`, `lint`, `secrets` — on every push to `main` and every PR. It grows with the milestones
(§13.4): `cloud` and `web` jobs, the tag-triggered release workflow, and the dependency-drift check
arrive at M5 / M6.

The rule from §13.2: **CI verifies, it never generates.** It compiles the *committed* Botan
amalgamation and fails if it will not build — it never runs `build_botan.sh`.

### `.clang-format`

```yaml
BasedOnStyle: LLVM
IndentWidth: 4
ColumnLimit: 100
AccessModifierOffset: -4
```

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  swift:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1       # the one third-party action; SHA-pin to lock it
        with:
          xcode-version: latest-stable           # or pin exactly: '26.6' (architecture.md §4.1)
      - run: swift --version
      - name: Cache SwiftPM build (holds the slow Botan compile)
        uses: actions/cache@v4
        with:
          path: Packages/PassFortKit/.build
          key: spm-${{ runner.os }}-${{ hashFiles('Packages/PassFortKit/Package.swift', 'Packages/PassFortKit/Package.resolved') }}
      - name: Build and test
        working-directory: Packages/PassFortKit
        run: |
          swift build
          swift test
      - name: Format check
        working-directory: Packages/PassFortKit
        run: swift format lint --strict --recursive Sources Tests

  native:
    runs-on: macos-15            # NOT Linux -- the amalgamation is configured for
    steps:                       # macos/arm64 in Phase 3 (build_botan.sh)
      - uses: actions/checkout@v4
      - name: Cache CMake build
        uses: actions/cache@v4
        with:
          path: native-tests/build
          key: cmake-${{ runner.os }}-${{ hashFiles('native-tests/CMakeLists.txt', 'Packages/PassFortKit/Sources/PFCrypto/vendor/botan/botan_all.cpp') }}
      - run: cmake -S native-tests -B native-tests/build
      - run: cmake --build native-tests/build
      - run: ctest --test-dir native-tests/build --output-on-failure

  lint:
    runs-on: ubuntu-latest       # shellcheck + clang-format ship on the image
    steps:
      - uses: actions/checkout@v4
      - run: shellcheck scripts/*.sh
      - name: clang-format -- our C++ only, never vendor/
        run: |
          files=$(git ls-files '*.cpp' '*.hpp' | grep -v '/vendor/' || true)
          [ -z "$files" ] || clang-format --dry-run -Werror $files

  secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0                        # full history for the scan
      - name: gitleaks -- backstop to the pre-commit hook
        run: |
          V=8.21.2                              # bump deliberately
          curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v${V}/gitleaks_${V}_linux_x64.tar.gz" | tar -xz gitleaks
          ./gitleaks detect --source . --redact --no-banner
```

### Before the first push

`-Werror` and `--strict` fail the pipeline on formatting drift, so normalise once, then make the first
push. The `origin` remote was added back in Phase 1; this is the point where local work first reaches
GitHub, and per `git-and-commits.md` the `git push` needs an explicit go-ahead:

```bash
cd /Users/csabimvp/dev/projects/PassFortApp

( cd Packages/PassFortKit && swift format --in-place --recursive Sources Tests )
clang-format -i $(git ls-files '*.cpp' '*.hpp' | grep -v '/vendor/')

git add -A
git commit -m "Add CI workflow and .clang-format; normalise formatting"
git push -u origin main                                    # CI runs on GitHub from here
```

**Checkpoint:** all four jobs green. `swift` and `native` each compile Botan once on a cold cache (a
few minutes); later runs restore the cache and finish fast.

**Notes**

- **macOS minutes.** `swift` and `native` both run on `macos-15` (bills at 10× Linux) and each
  recompiles Botan through a different build system. If minutes bite, merge them into one job that runs
  both sequentially, or move to a self-hosted runner (`architecture.md` §14, open decision 16).
- **`maxim-lobanov/setup-xcode`** is the only non-`actions/*` dependency — SHA-pin it if you want CI's
  own supply chain locked (the §3.2 A7 posture applies here too).
- **`deps` job** (assert lockfiles have not drifted, §13.2) is a no-op until GRDB arrives at M2 — add it
  then.
- Once this is green on `main`, add the build-status badge to `README.md` — the README convention earns
  a badge only when CI actually runs.

---

## Phase 6 — The Xcode app project (defer until M3)

Not needed to build M1–M2. When the GUI starts:

1. **Xcode -> File -> New -> Project -> macOS -> App.** Name it `PassFort`, SwiftUI, Swift. Save it at
   the repo root so `PassFort.xcodeproj` sits next to `Packages/`.
2. **File -> Add Package Dependencies -> Add Local...** -> select `Packages/PassFortKit`. Add
   `PassFortVault` (and `PassFortCrypto` if the app needs it directly) to the app target.
3. New Xcode targets use **file-system synchronized groups** by default — create, rename, and delete
   files in the filesystem and Xcode picks them up. **Never hand-edit `project.pbxproj`** (`xcode.md`).
4. The fast loop stays `swift test` in `Packages/PassFortKit`. Use Xcode to run the app and for signing
   and entitlements (M4), which are GUI-driven.
5. `xcodebuild -list`, then
   `xcodebuild test -scheme PassFort -destination 'platform=macOS'` verifies from the CLI.

---

## Where this leaves you

- **M0 complete:** the seam is real, exercised from Swift and from a native C++ test, and the layering is
  compiler-enforced.
- **M1 scaffolding ready:** Botan linked, CMake harness live, CI green on every push
  (`swift` / `native` / `lint` / `secrets`).
- **Next (M1 proper):** implement the real §6.2 surface — `pf_kdf_calibrate`, `pf_vault_create`,
  `pf_session_open`, `pf_seal` / `pf_open`, `pf_mac_*` — split `boundary/` into `keyring/`, `aead/`,
  `util/` behind a shared internal `Bytes` header, and add the RFC 9106 / 8439 / 5869 known-answer tests
  to `native-tests/`.

## Known deviation from `architecture.md` §4

The §4 tree shows `Tools/passfort-cli/` as a sibling of `Packages/`, but a SwiftPM target cannot live
outside its package root. This runbook places the CLI at
`Packages/PassFortKit/Sources/passfort-cli/`. To restore the original layout, either move `Package.swift`
to the repo root or make the CLI its own package. Worth an `architecture.md` footnote or a short ADR.
