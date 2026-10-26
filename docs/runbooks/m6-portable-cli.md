# M6 — Portable CLI (Linux first)

**Status:** Phase 0, the spike, ran in CI on 2026-10-26 (branch `m6-spike`, not merged; runs
`40334650317` to `40343656728`). Its WSL2 half (0.7) is still to run, on the Windows PC. Phases 1–7
are a plan built from the spike's results. Treat each step and checkpoint as provisional until
0.7 is in and the decisions in 0.8 are recorded.

**Prerequisite:** M5 complete (it is). M6 doesn't depend on M7, and M7 doesn't depend on M6.

**Spec:** `architecture.md` §11 (the portable CLI and the table of what the port replaces), §14.21
(the open choices this spike settles), §9.4 (pinning rules the Linux transport must keep), §3.4
(the memory-locking limitation this spike found to be wrong today), §13.2 (the `linux` CI job).
ADR-0010 is the decision. ADR-0001 holds the Botan vendoring rules the second amalgamation amends.

---

## What M6 delivers

`passfort-cli` builds and passes the package's suites on Linux x86_64, and runs in WSL2 on a
Windows machine against the same vault format and the same sync API, with pinning. No command,
format, protocol or seam change. The port replaces the Apple-only code in §11.2 and nothing else.

### What is not in M6

- Native Windows, Linux on arm64, and a packaged binary (`.deb` or similar). The CLI is built in
  WSL2 with the Swift toolchain (0.6).
- Any change to the app beyond what the shared package changes (the app must keep building and
  passing).

---

## Phase 0 — Spike results

Everything ran on GitHub's `ubuntu-24.04` runners in the `swift:6.3.3-noble` container, with
`.github/workflows/m6-spike.yml` and the probes in `spikes/m6/` on the `m6-spike` branch.

### 0.1 Pinning on Linux (§14.21 a): libcurl with an OpenSSL verify callback

**The `URLSession` route doesn't exist.** swift-corelibs-foundation marks
`NSURLAuthenticationMethodServerTrust` and `URLProtectionSpace.serverTrust` `unavailable` and never
issues a server-trust challenge. Its only CA override (`URLSessionCertificateAuthorityInfoFile`) is
compiled for Android only. `tlsMinimumSupportedProtocolVersion` isn't there either. On Linux a
`URLSession` can't pin and can't require TLS 1.3.

**libcurl's own pinning option checks the leaf only.** `CURLOPT_PINNEDPUBLICKEY` with the
intermediate's key fails (`curl=90`), with the leaf's key it passes. §9.4 pins CA keys because Azure
renews the leaf, so this option can't be used.

**What works:** libcurl with `CURLOPT_SSL_CTX_FUNCTION`, which installs an OpenSSL
`SSL_CTX_set_cert_verify_callback`. The callback runs OpenSSL's normal chain verification first,
then requires a pinned SPKI hash anywhere in the verified chain, root included. That is exactly
what `PinnedTransport.evaluate` does with `SecTrustEvaluateWithError` and
`SecTrustCopyCertificateChain`. libcurl still checks the hostname itself. The probe
(`spikes/m6/pinning/`, about 100 lines of C) gave, against `github.com` with pins read from the
live chain:

| Case | Want | Got |
|---|---|---|
| system CAs, no pins | pass | pass |
| intermediate pinned | pass | pass |
| root pinned (the anchor OpenSSL verified to) | pass | pass |
| leaf pinned | pass | pass |
| only a bogus pin | fail | fail (`application verification failure`) |
| bogus + intermediate (any one pin is enough) | pass | pass |
| intermediate pinned, wrong hostname | fail | fail (pin matched, then the hostname check refused) |
| self-signed server with its own key pinned | fail | fail (pins add to trust, never replace it) |
| `CURLOPT_PINNEDPUBLICKEY`, intermediate | fail | fail |
| `CURLOPT_PINNEDPUBLICKEY`, leaf | pass | pass |

**Cost:** no new runtime library. Foundation's networking on Linux is built on libcurl, so the
release CLI already loads `libcurl.so.4`, `libssl.so.3` and `libcrypto.so.3` (0.6). Building needs
`libcurl4-openssl-dev` and `libssl-dev`. The transport is new code to own: a C target, request and
response plumbing, the 15 s timeout, no redirects (`CURLOPT_FOLLOWLOCATION 0`), the TLS 1.3 floor
(`CURLOPT_SSLVERSION`), and mapping the pin failure to `SyncError.pinningFailed`.

**The other choice, no pinning on Linux at first,** would contradict §9.4 ("a pin failure stops
sync, never a silent fallback"). It would need a §3.4 entry and an explicit opt-in, so it isn't
proposed.

### 0.2 Replacing CryptoKit (§14.21 b): libcrypto, through the same C target

| | swift-crypto 5.0.3 | OpenSSL libcrypto |
|---|---|---|
| Code change | none: `import Crypto` instead of `CryptoKit` | `HMAC()` and `SHA256()` through the C target 0.1 needs anyway |
| New dependencies | swift-crypto + swift-asn1, resolved on every platform (two new `Package.resolved` pins on macOS too) | none (a system library already loaded) |
| Cold build | 70 s for 482 compile steps (BoringSSL) | negligible |
| RFC 6238 vectors (SHA-1/256/512, T=59 and T=1111111109) | pass (`OneTimeCodeTests` on Linux) | pass (the probe's `hmac-kats`) |

**Proposed: libcrypto.** The C target exists for pinning anyway, and the minimal-dependencies rule
prefers a platform library. Apple builds keep CryptoKit, so there are two code paths behind
`#if canImport(CryptoKit)`. The same `OneTimeCodeTests` vectors cover both, because CI runs them on
both platforms.

### 0.3 The second Botan amalgamation (§11.2): generated on the Mac, side by side

- `scripts/build_botan.sh <macos-arm64|linux-x86_64>` writes `vendor/botan/<target>/`. The only
  module difference is AES hardware (`aes_armv8` or `aes_ni`). The Linux one is generated on the Mac
  with `--disable-cc-tests`, which skips configure's host-compiler probe. Compared with a probe
  forced to x86_64, the output differs in comments only.
- `vendor/botan/botan_all.{h,cpp}` are three-line `#if` shims that include the right target.
  `Package.swift` excludes the target folders so SwiftPM compiles only the shim. Any other target hits
  an `#error`.
- **Regenerating the macOS amalgamation is byte-identical**, so the move is a pure rename.
- **The Linux one passes all 64 native tests** (RFC 9106, 8439 and 5869 known-answer tests, tamper,
  seam fuzz). It's 587 KB of `.cpp`, against 536 KB for macOS.
- **Cross-host agreement holds both ways (§11.5):** the macOS-written fixture vaults pass in the
  Linux test run, and a vault created by the Linux CLI opens on the Mac.

### 0.4 Botan's locking allocator (§14.21, §3.4): not compiled in, on either platform

**Finding:** `BOTAN_HAS_LOCKING_ALLOCATOR` isn't defined in the vendored amalgamation, macOS
included. ADR-0001's module list never had `locking_allocator`, and `--minimized-build` only
includes what's listed. Today `secure_vector` zeroizes on free but never `mlock`s. §3.4's
"`mlock` (via Botan's locking allocator) is best-effort" is false today, and so is ADR-0004's
"with a locking allocator". This applies to the Mac app now, not only to M6.

With the module added (Linux probe, `spikes/m6/memlock/`, `VmLck` from `/proc/self/status`):

| `ulimit -l` | Locked |
|---|---|
| 8192 KiB (Ubuntu's default) | a 512 KiB pool, locked at startup |
| 64 KiB | 64 KiB (the pool shrinks to fit) |
| 0, or `BOTAN_MLOCK_POOL_SIZE=0` | nothing; silent fallback to ordinary memory, no crash |

**Proposed:** add `locking_allocator` to the module set for both targets, regenerate both
amalgamations (a reviewed ADR-0001 amendment commit), and verify on macOS that the pool is locked
(no `/proc` there: check `mlock`'s result or use `vmmap`). This is Phase 1, and it is worth doing
even if M6 waits.

### 0.5 What else the Linux build needed

The package needed only these changes, all done on the spike branch:

| Gap on Linux | Fix |
|---|---|
| `os` (`OSAllocatedUnfairLock`) | `Locked<Value>` over `NSLock`, same `withLock` shape (`Synchronization.Mutex` needs macOS 15; the package targets 14) |
| `URL.applicationSupportDirectory` | `FileManager`'s lookup, which gives the XDG data home (`~/.local/share/PassFort/`) |
| `URLSession` lives in `FoundationNetworking` | `#if canImport(FoundationNetworking)` imports (four files) |
| `tlsMinimumSupportedProtocolVersion` | none on `URLSession`; the libcurl transport sets it (0.1) |
| Header names come back capitalized (`X-Passfort-Token`) | a case-insensitive lookup in the test stub; the wire is unaffected (header names are case-insensitive) |
| `CryptoKit`, `Security` | 0.1, 0.2 |

With those changes, **all 272 tests pass on Linux** (256 vault + 16 boundary; the 7 `SecTrust`
pinning tests are Apple-only), and all 279 still pass on macOS. GRDB 7.11.1 builds and passes
against the system `libsqlite3-dev`.

**Scripting the CLI:** glibc's `getpass` flushes queued input before it reads, so a password piped
in ahead of the prompt is thrown away and the command hangs. `init`, `add` and `get` work at a
terminal. Scripts drive it through a pty (`spikes/m6/cli_smoke.py`). There is deliberately no
stdin-password mode, and this isn't a reason to add one.

### 0.6 Distribution: build in WSL2 with the toolchain

- The dynamic release binary is 38 MB and needs about 77 MB of Swift runtime libraries from
  `/usr/lib/swift/linux`, plus `libsqlite3`, `libstdc++`, `libcurl`, `libssl` and `libcrypto`.
- **`--static-swift-stdlib` fails:** the toolchain ships no static `libswiftCxx` or
  `libswiftCxxStdlib`, so a target built with C++ interop (`PassFortCrypto`) can't be linked that way.
- **The static Linux SDK (musl) fails too:** GRDB's `GRDBSQLite` module needs `sqlite3.h`, and the
  SDK ships no SQLite. Getting past that means vendoring SQLite's source, which isn't worth it for M6.
- **Proposed:** the CLI is built where it runs, with Swift installed via `swiftly`. A copied binary
  is not a goal for M6.

### 0.7 WSL2 (to run on the Windows PC)

CI can't answer these questions: the WSL2 kernel's `RLIMIT_MEMLOCK`, whether WAL works for a vault
under `/mnt/c` (§11.3 expects it not to), and whether the build, tests, pinning probe and CLI behave
the same in WSL2. From a clone of `m6-spike` inside the WSL filesystem:

```bash
sudo apt-get install -y libsqlite3-dev libcurl4-openssl-dev libssl-dev python3 clang git openssl
spikes/m6/wsl-check.sh 2>&1 | tee ~/m6-wsl-check.log
```

It writes only under `~/m6-wsl-check/` and `/mnt/c/Users/<you>/m6-wsl-check/`, and ends with a
summary. Record the result here.

### 0.8 Decisions to record before Phase 1

1. **ADR-0011: TLS pinning on Linux through libcurl with an OpenSSL verify callback** (0.1), and
   libcrypto for HMAC and SHA-256 there (0.2). It's a security-relevant choice with a rejected
   dependency, so it gets an ADR.
2. **ADR-0001 amendment:** one amalgamation per target under `vendor/botan/<target>/`, and
   `locking_allocator` in the module set (0.3, 0.4).
3. **`architecture.md` rev 18:** §3.4 (the locking allocator, true once Phase 1 lands), §11.2 (the
   table's *spike* entries resolved), §14.21 (a) and (b) resolved, §11.3 with the 0.7 results.

---

## Phase 1 — The locking allocator, on the Mac first

Add `locking_allocator` to `build_botan.sh`, regenerate the macOS amalgamation, and confirm on the
Mac that keys land in the locked pool. One reviewed commit with the ADR-0001 amendment. Fix §3.4 and
ADR-0004's claim in the same change. This is independent of Linux.

**Checkpoint:** `swift test`, `native` (plain and ASan/UBSan) and the app's tests pass. The locked
pool is visible on macOS.

## Phase 2 — The second amalgamation

Port the spike's `build_botan.sh` targets, the `#if` shims, the `exclude:` and the Linux
amalgamation (now with `locking_allocator`) to `main`. Point `native-tests` and the CI cache key at
the shim, which they already compile unchanged.

**Checkpoint:** macOS is byte-identical apart from the rename; macOS CI is green.

## Phase 3 — The platform shims

`Locked`, the Application Support lookup, the `FoundationNetworking` imports and the
case-insensitive header lookup (0.5), each with the test that covers it. No behaviour change on
macOS.

## Phase 4 — `CLinuxTLS`: pinned transport, HMAC, SHA-256

A C target compiled on Linux only (`.when(platforms: [.linux])`) against the system libcurl and
OpenSSL. It holds the probe's verify callback grown into a request function, plus HMAC and SHA-256.

- `HTTPSyncAPI` sends through a small transport protocol: `URLSession` with `PinnedTransport` on
  Apple, `CLinuxTLS` on Linux. `HTTPSyncAPITests` stub at that protocol on both platforms instead of
  through `URLProtocol`, so the request-building tests run on Linux unchanged.
- Offline pinning tests on Linux drive the verify function with the checked-in
  `Fixtures/pinning/{leaf,int,root}.der`, mirroring `PinningTests`' `SecTrust` cases (fixed verify
  time, anchors only, no network).
- `OneTimeCode` and `spkiHash` use CryptoKit on Apple and `CLinuxTLS` on Linux.

**Checkpoint:** every `PinningTests` case has a Linux twin, and both platforms pass `OneTimeCodeTests`.

## Phase 5 — The `linux` CI job

The package suites and `native` on `ubuntu-24.04` in `swift:6.3.3-noble` (§13.2), with the
`-dev` packages from 0.1. `deps` keeps checking `Package.resolved`, which doesn't change if 0.2's
libcrypto choice holds.

## Phase 6 — The WSL2 checkpoint

On the Windows PC, in WSL2: build, `swift test`, then join the real vault from
`rg-passfort-dev` with the CLI and pins, and run the two-device drill with the Mac app as the other
device (§13.1). The vault stays in the WSL filesystem (0.7).

**Checkpoint (the milestone's):** an edit on the Mac appears in the WSL2 CLI after `sync`, and the
reverse. A wrong pin stops sync with `pinningFailed`.

## Phase 7 — Doc sweep

`architecture.md` (§11, §13.2, §14.21, Appendix A), `development.md` (the Linux loop),
`SECURITY.md` (Linux pinning, the locking allocator), the README's requirements and a short "CLI on
Linux / WSL2" section, and the runbook index. Delete the `m6-spike` branch once the runbook carries
its results (ask first).
