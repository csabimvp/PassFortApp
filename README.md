# PassFort

macOS-first SwiftUI password manager built around a deliberately tiny Swift↔C++ crypto core (Botan 3),
with per-record envelope encryption and a custom Azure sync backend.

## Status

Status: active hobby project. Milestone M0 (toolchain + seam + scaffolding) is complete; M1 (the crypto
core) is in progress. CI runs on every push (`swift` / `native` / `lint` / `secrets` jobs). No release
yet.

## Overview

PassFort keeps every secret key inside a small C++ module and lets nothing else touch key material.
Swift owns storage, the data model, the UI, and sync; it can ask the C++ session to seal or open bytes
but can never ask for a key. That single boundary — which bytes live where — is the security property
the project is organised around, not the mere fact that C++ is involved.

The vault format is language-agnostic by design so the same sealed vault can be opened by the macOS
app, the `passfort-cli` tool, and (later) a browser client running the same core compiled to
WebAssembly. Milestones M1 and M2 are built and tested entirely through `passfort-cli`, before the GUI
exists.

`docs/architecture.md` (rev 7) is the specification the project is built against; read it before
changing anything. The seven ADRs in `docs/adr/` hold the reasoning behind every load-bearing choice.

## Architecture

Three build systems, one real one:

- **SwiftPM** (`Packages/PassFortKit/Package.swift`) is the actual build. It compiles four targets
  top to bottom:
  - `PFCrypto` (C++) — owns every key and nothing else: Argon2id, the HKDF key hierarchy, DEK
    wrap/unwrap, record seal/open, the vault-header codec, the streaming manifest MAC. Botan 3 is
    vendored under `Sources/PFCrypto/vendor/botan/` as a two-file amalgamation so its headers never
    reach the Swift compiler. No interop flag on this target.
  - `PassFortCrypto` (Swift) — the **only** module compiled with `.interoperabilityMode(.Cxx)`.
    `import PFCrypto` appears here and nowhere else. `actor VaultSession` owns the opaque C++ session
    handle and turns `PFStatus` codes into Swift errors. Built with `-enable-library-evolution` so the
    interop mode does not go viral to its clients.
  - `PassFortVault` (Swift, no interop flag) — SQLite storage, schema and migrations, the data model,
    search, tombstones, the sync client. **Cannot** `import PFCrypto` — the missing interop flag turns
    a layering violation into a compile error. GRDB is added at M2.
  - `passfort-cli` (Swift executable) — exercises the full seam from M1; the primary interface for
    M1 and M2.
- **CMake** (`native-tests/`) builds only the Catch2 unit tests over `PFCrypto`'s C++ internals — RFC
  known-answer tests, tamper tests, seam fuzzing. It never touches the app build graph.
- **Xcode project** — a thin shell around the SwiftPM package, added when the GUI starts (M3).

Key decisions and their ADRs: Botan as a static minimized amalgamation (`docs/adr/0001`); the
`noexcept` / opaque-handle / POD-only seam style (`docs/adr/0002`); per-record envelope encryption in
SQLite (`docs/adr/0003`); **Swift owns storage, C++ owns only keys** (`docs/adr/0004`, which amends
0002 and 0003); a custom Azure sync backend rather than CloudKit (`docs/adr/0005`); the web client
running the core as WebAssembly (`docs/adr/0006`); the recovery-key DEK slot folded into header format
v1 with no migration (`docs/adr/0007`).

## Project structure

```
PassFortApp/
├── CLAUDE.md                        # guidance for Claude Code; the canonical Commands list
├── README.md                       # this file
├── Packages/
│   └── PassFortKit/                 # the local SwiftPM package — the entire core lives here
│       ├── Package.swift            # 4 targets + 1 test target; only PassFortCrypto has the Cxx flag
│       ├── Sources/
│       │   ├── PFCrypto/            # C++ — keys only: Argon2id, HKDF, seal/open, header, manifest MAC
│       │   │   ├── include/PFCrypto/  # PUBLIC headers — the only thing Swift's importer sees
│       │   │   ├── internal/          # shared C++ headers, NOT exported: Secure/Bytes/Canonical.hpp
│       │   │   ├── boundary/          # noexcept POD facade (bytes.cpp; session/record/manifest in M1)
│       │   │   └── vendor/botan/      # Botan 3.13.0 amalgamation (botan_all.{h,cpp}) — ADR-0001
│       │   ├── PassFortCrypto/      # Swift — the ONLY .interoperabilityMode(.Cxx) module; VaultSession
│       │   ├── PassFortVault/       # Swift — storage/model/sync; cannot import PFCrypto (enforced)
│       │   └── passfort-cli/        # Swift executable — primary interface for M1-M2
│       └── Tests/
│           └── PFCryptoBoundaryTests/ # Swift-side seam tests (sanctioned interop exception)
├── native-tests/                   # CMake + Catch2 tests over PFCrypto internals — outside app build
│   ├── CMakeLists.txt               # each .cpp listed explicitly; add files as milestones create them
│   ├── tests/                       # test_bytes, test_kat_*, test_header_codec, (tamper/fuzz in M1)
│   └── build/                       # generated, git-ignored
├── scripts/
│   └── build_botan.sh               # regenerate the minimized Botan amalgamation — run deliberately
└── docs/
    ├── architecture.md              # the specification (rev 7); stable §-numbers referenced everywhere
    ├── adr/                         # 7 ADRs — reasoning behind load-bearing choices
    ├── bootstrap.md                 # M0 runbook (toolchain → seam → Botan → CMake → CI)
    └── runbooks/                    # per-milestone build runbooks (M1 onward)
```

## Getting started

### Prerequisites

| Tool | Version | Notes |
|---|---|---|
| macOS | 14+ (Sonoma) | Apple Silicon or Intel |
| Xcode | 26.6 | provides Swift 6.3.3 and clang 21; C++ interop is stable on this toolchain |
| CMake | 4.4+ | `brew install cmake`; builds `native-tests/` only |
| Python | 3.x | only needed to regenerate the vendored Botan amalgamation |
| Botan | 3.13.0 | vendored and committed; a Homebrew install is needed only to run `scripts/build_botan.sh` |

Botan itself does not need to be installed to build or test the project — the amalgamation is in the
repo (ADR-0001).

### Install

```bash
# 1. Point the toolchain at Xcode, not CommandLineTools (xcodebuild and the Swift 6.3 toolchain).
sudo xcode-select -s /Applications/Xcode.app

# 2. Build tools for the native C++ test harness.
brew install cmake

# 3. Build the core (fast loop — roughly 10x quicker than Xcode for core work).
cd Packages/PassFortKit && swift build

# 4. Configure and build the native C++ tests (from the repo root).
cmake -S native-tests -B native-tests/build && cmake --build native-tests/build

# 5. Verify everything is green.
cd Packages/PassFortKit && swift test
ctest --test-dir native-tests/build          # run from the repo root
```

## Usage

`passfort-cli` is the primary interface for M1 and M2. Run it from `Packages/PassFortKit/`.

Today (M0 seam check):

```bash
cd Packages/PassFortKit && swift run passfort-cli
# -> seam OK -- 19 bytes round-tripped through C++
# -> botan 3.13.0
```

Planned subcommands (M1 Phase 10 — not wired yet):

```bash
passfort-cli bench  [--target-ms 500]                    # calibrate Argon2id; print params + timing
passfort-cli init   <vault.pfvault>                       # create a vault; prompt for password (no echo)
passfort-cli unlock <vault.pfvault>                       # open a session; report OK / AuthFailed
passfort-cli seal   <vault> --id <uuid> --in <file>       # seal a record; write the sealed blob
passfort-cli open   <vault> --id <uuid> --in <sealed>     # open a record; write the plaintext
```

## Testing

### What to run, and when

| Situation | Command(s) |
|---|---|
| Edited Swift, or C++ that Swift compiles (`Sources/PFCrypto/`) | `swift build` then `swift test` (in `Packages/PassFortKit/`) |
| Edited a `.cpp` / `.hpp` under `native-tests/` or `Sources/PFCrypto/` | `cmake --build native-tests/build` then `ctest --test-dir native-tests/build` |
| Added a file to `native-tests/CMakeLists.txt` (new source or test) | re-run `cmake -S native-tests -B native-tests/build` first, then build |
| Before a commit / at a runbook checkpoint | full `swift test` **and** `ctest --test-dir native-tests/build --output-on-failure` |
| Touched a boundary function (`pf_*`) | also run the sanitizer build (below) |
| Regenerated the Botan amalgamation | rebuild both: `swift build` and a clean `cmake --build` |

### Daily loop (SwiftPM)

```bash
cd Packages/PassFortKit && swift build      # compile all four targets
cd Packages/PassFortKit && swift test       # run the Swift test targets (PFCryptoBoundaryTests today)
swift test --filter PFCryptoBoundaryTests   # a single suite, from inside Packages/PassFortKit/
```

`swift build` also compiles every `.cpp` under `Sources/PFCrypto/` automatically — new files in
`keyring/`, `aead/`, `manifest/` join the build the moment they exist, with no `Package.swift` edit.

### Native C++ tests (CMake + Catch2)

Run these from the **repo root** — the paths carry the `native-tests/` prefix.

```bash
# Configure: generates native-tests/build/. Re-run after ANY edit to native-tests/CMakeLists.txt
# (for example after adding a new test file to the add_executable list). A file named there that
# does not exist yet fails this step, not the build.
cmake -S native-tests -B native-tests/build

# Build: compiles the Catch2 test binary. Enough on its own after editing only .cpp / .hpp files.
cmake --build native-tests/build

# Run all tests.
ctest --test-dir native-tests/build

# Run with failure output, or filter by test-case name (a regex over the name string, NOT the
# Catch2 [tag] — e.g. "-R kat" matches every test whose name starts with "kat ").
ctest --test-dir native-tests/build --output-on-failure
ctest --test-dir native-tests/build -R kat

# Or drive the binary directly for Catch2 tag filtering:
./native-tests/build/pfcrypto_tests "[kat]"
```

The `native-tests/` harness deliberately reaches past the `boundary/` facade to exercise `keyring/`,
`aead/`, and `manifest/` directly — the one sanctioned exception to the layering rules
(`architecture.md` §13).

### Sanitizer build (ASan + UBSan)

Required after touching any boundary function; enforced in CI on every push from M1 onward. Use a
separate build directory so it does not fight the normal one.

```bash
cmake -S native-tests -B native-tests/build-san \
  -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined"
cmake --build native-tests/build-san
ctest --test-dir native-tests/build-san --output-on-failure
```

ASan instruments every load/store to catch buffer overflows, use-after-free, and leaks at the moment
they happen; UBSan traps signed-integer overflow, bad shifts, null dereference, and misaligned access.
A sanitizer report is a test failure even if every assertion passed. Both roughly double run time, so
this is a separate build, not the default.

### Full app (M3+)

Not wired yet — the Xcode project is added when the GUI starts. Once it exists
(run `xcodebuild -list` first to confirm the scheme name):

```bash
xcodebuild -scheme PassFort -destination 'platform=macOS' build
xcodebuild test -scheme PassFort -destination 'platform=macOS'
```

### Regenerating vendored crypto (run deliberately, never automatically — ADR-0001)

```bash
scripts/build_botan.sh        # regenerate the minimized Botan 3.13.0 amalgamation
scripts/build_wasm.sh         # PFCrypto -> pfcrypto.wasm via Emscripten   (M6 — not present yet)
scripts/calibrate_kdf.sh      # measure Argon2id parameters for this machine   (M1 — not present yet)
```

CI never runs these — it builds against the committed amalgamation. Upgrading the Botan pin is an
explicit, reviewable commit; the version is recorded in the vault header.

## Further documentation

- `docs/architecture.md` — the full specification: threat model, data models, vault format, roadmap.
- `docs/adr/` — the seven architecture decision records; `docs/adr/README.md` is the template and index.
- `docs/bootstrap.md` — the M0 runbook (toolchain → seam → Botan → CMake harness → CI).
- `docs/runbooks/` — per-milestone build runbooks (M1 onward) and the series index.
