# M6 — Portable CLI (Linux first)

**Status:** Phase 0 and Phase 1 done. The spike ran in CI on 2026-10-26 (branch `m6-spike`, not
merged; runs `40334650317` to `40343656728`) and in WSL2 on 2026-10-29 (0.7, all checks pass).
Phase 1 landed 2026-10-26; Phase 2, the last of 0.8, and Phases 3, 4 and 5 on 2026-10-29;
Phase 6, the milestone's checkpoint, and Phases 7 and 8 on 2026-10-30. **M6 is done** apart
from one by-hand check, deferred: Phase 7's Windows clipboard in WSL2.

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

### 0.7 WSL2 (on the Windows PC): everything passes

CI can't answer these questions: the WSL2 kernel's `RLIMIT_MEMLOCK`, whether WAL works for a vault
under `/mnt/c` (§11.3 expected it not to), and whether the build, tests, pinning probe and CLI behave
the same in WSL2. From a clone of `m6-spike` inside the WSL filesystem:

```bash
sudo apt-get install -y libsqlite3-dev libcurl4-openssl-dev libssl-dev python3 clang git openssl
spikes/m6/wsl-check.sh 2>&1 | tee ~/m6-wsl-check.log
```

It writes only under `~/m6-wsl-check/` and `/mnt/c/Users/<you>/m6-wsl-check/`, and ends with a
summary.

**Ran 2026-10-29** on WSL2 kernel 6.18.33.2, **Ubuntu 22.04.5** and **Swift 6.4.1** (swiftly's
default, not the pinned 6.3.3; CI runs Ubuntu 24.04). All eight checks passed:

| Check | Result |
|---|---|
| `swift build`, `swift test` | 256 vault + 16 boundary tests pass, as in CI |
| CLI `init` / `add` / `get`, vault under `~` | pass |
| The same, vault under `/mnt/c` | pass |
| WAL, two connections in one process (snapshot read across a write) | pass under `~` **and** under `/mnt/c` |
| Pinning probe (libcurl 7.81 here, 8.5 in CI) | all ten scenarios as expected; TOTP vectors match |
| `RLIMIT_MEMLOCK` | **64 MiB**; Botan locks its full 512 KiB pool (`VmLck` 512 kB) |

**What `/mnt/c` passing does and doesn't show.** §11.3 expected WAL to fail there and it didn't:
WAL mode, shared memory and a snapshot read all work for one process. Not tested: two processes on
the same vault at once (the CLI's `sync` while another command runs), or a Windows program
(Explorer preview, antivirus, a cloud-sync client) opening the file while the CLI has it. POSIX
locks taken in WSL aren't promised to mean anything to Windows. The rule stays: **the vault lives
in the WSL filesystem.** Nothing in M6 needs `/mnt/c`, so this isn't worth more testing.

**Toolchain.** The package also passes on Swift 6.4.1 and Ubuntu 22.04, so neither is a blocker. The
Phase 6 checkpoint still runs on the pinned toolchain: `swiftly install 6.3.3 && swiftly use 6.3.3`.

### 0.8 Decisions to record before Phase 1

1. **ADR-0011: TLS pinning on Linux through libcurl with an OpenSSL verify callback** (0.1), and
   libcrypto for HMAC and SHA-256 there (0.2). **Recorded 2026-10-26** (`architecture.md` rev 19).
2. **ADR-0001 amendment:** one amalgamation per target under `vendor/botan/<target>/` (0.3).
   The `locking_allocator` half (0.4) landed with Phase 1, the per-target half with Phase 2
   (2026-10-29, `architecture.md` rev 22).
3. **`architecture.md`:** §3.4 and the locking allocator landed in rev 18; §11.2's *spike* rows and
   §14.21 (a) and (b) in rev 19; §11.3 and §3.4's WSL2 limit, from 0.7, in rev 21.

---

## Phase 1 — The locking allocator, on the Mac first

> **Done 2026-10-26** (`architecture.md` rev 18, ADR-0001 amendment). On macOS the limit is
> unlimited, so Botan locks its full 512 KiB pool at startup. The sandboxed app wires 560 KiB
> against 48 KiB for the previous build (`proc_pid_rusage`, `ri_wired_size`). The pool serves only
> allocations of 16–256 bytes, which covers every key; larger buffers fall back to ordinary
> memory (§3.4). `internal/Secure.hpp` refuses to compile without the module, and
> `native-tests/tests/test_secure_memory.cpp` checks the pages are locked. It skips under ASan,
> which makes `mlock` a no-op. Native (65), package (279) and app suites pass.

Add `locking_allocator` to `build_botan.sh`, regenerate the macOS amalgamation, and confirm on the
Mac that keys land in the locked pool. One reviewed commit with the ADR-0001 amendment. Fix §3.4 and
ADR-0004's claim in the same change. This is independent of Linux.

**Checkpoint:** `swift test`, `native` (plain and ASan/UBSan) and the app's tests pass. The locked
pool is visible on macOS.

## Phase 2 — The second amalgamation

> **Done 2026-10-29** (ADR-0001 amendment, `architecture.md` rev 22). The macOS amalgamation moved
> to `vendor/botan/macos-arm64/`. Regenerating it with the new script gives the same bytes (SHA-1
> of `botan_all.{h,cpp}` unchanged). `linux-x86_64/` is generated on the Mac, with
> `locking_allocator`. The spike's `PF_BOTAN_EXTRA_MODULES` / `PF_BOTAN_OUT` knobs were dropped,
> since the module is in the standard set now; the spike's `swift-crypto` dependency was not
> brought over (ADR-0011). Package (265 + 16), native (65, and 62 under ASan/UBSan, which leaves
> a few out by design) and app suites pass on the Mac. Linux compiles the new amalgamation for
> the first time in Phase 5's CI job.

Port the spike's `build_botan.sh` targets, the `#if` shims, the `exclude:` and the Linux
amalgamation (now with `locking_allocator`) to `main`. Point `native-tests` and the CI cache key at
the shim, which they already compile unchanged.

**Checkpoint:** macOS is byte-identical apart from the rename; macOS CI is green.

## Phase 3 — The platform shims

> **Done 2026-10-29**, one commit per shim. `Locked` (`LockedTests`), `PlatformPaths`
> (`PlatformPathsTests`), the `FoundationNetworking` imports in `HTTPSyncAPI`, `PinnedTransport`
> and `HTTPSyncAPITests`, and the stub's case-insensitive `header(_:)`
> (`capturedHeadersMatchInAnyCase`). The spike's import in `FakeSyncServer` isn't needed on
> `main`. The CLI already keeps its files under `~/.config/passfort/` and its clipboard code
> behind `canImport(AppKit)`, so it needed nothing. Package (271 + 16) and app suites pass.
> The package doesn't build on Linux yet: `CryptoKit` and `Security` are Phase 4.

`Locked`, the Application Support lookup, the `FoundationNetworking` imports and the
case-insensitive header lookup (0.5), each with the test that covers it. No behaviour change on
macOS.

## Phase 4 — `CLinuxTLS`: pinned transport, HMAC, SHA-256

> **Done 2026-10-29** (PR #1, ADR-0011). `HTTPSyncAPI` sends through `SyncTransport`:
> `URLSessionTransport` with `PinnedTransport` on Apple platforms, `CurlTransport` over `CLinuxTLS`
> on Linux. `PinSet` and its helpers (`isLoopback`, `spkiHash`) moved to a shared file;
> `PlatformCrypto` picks CryptoKit or libcrypto for SHA-256 and HMAC. `CLinuxTLS` compiles to
> nothing on Apple platforms. Beyond the plan, `pf_tls_send`:
>
> - refuses a pinned request that isn't https **before sending** (redirects are off, so the scheme
>   can't change), and treats a request that ended without the pin check passing as untrusted;
> - fails closed when libcurl isn't on OpenSSL (`.pinningFailed`, no new `SyncError` case);
> - refuses header lines with CR, LF or NUL (`.badRequest`), caps a response at 64 MiB
>   (`.invalidResponse`), turns off TLS session reuse (a resumed session would skip the callback)
>   and `Expect: 100-continue`, and treats the 15 s timeout as an idle limit, as `URLSession` does.
>
> Tests: `HTTPSyncAPITests` stub the protocol on both platforms; `URLSessionTransportTests` keep
> the `URLProtocol` and redirect cases (Apple); `PinSetTests` run on both; `LinuxPinningTests` are
> `PinningTests`' twins through `pf_tls_verify_chain`; `CurlTransportTests` drive libcurl against
> a one-shot loopback server (request and response, no body on GET, redirects unfollowed, offline,
> header splitting, cancellation, and pinned http refused before a byte goes out). Linux: 295
> package tests pass. Mac: 273 + 16, and the app. Not covered offline: a live pinned handshake,
> which is Phase 6's drill.

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

> **Done 2026-10-29**, with Phase 4, since nothing else compiled its Linux code. `swift build` and
> `swift test` in `swift:6.3.3-noble`, then `CLinuxTLS`'s callers under ASan with leak checking
> (suppressing only libXCTest, `.github/lsan-suppressions.txt`), then the native suites. Its first
> runs found three things, each fixed in its own commit: a pointer conversion Linux's compiler
> wouldn't infer, Phase 3's `PlatformPathsTests` reading the passwd home where Foundation reads
> `$HOME` (they differ in the container), and the test server's thread outliving its test.
> Green on run `40964037856`: 295 package tests, 27 under ASan with no leaks, 65 native.
> `Package.resolved` is unchanged.

The package suites and `native` on `ubuntu-24.04` in `swift:6.3.3-noble` (§13.2), with the
`-dev` packages from 0.1. `deps` keeps checking `Package.resolved`, which doesn't change if 0.2's
libcrypto choice holds.

## Phase 6 — The WSL2 checkpoint

> **Done 2026-10-30** (the maintainer's run on the Windows PC). Swift 6.3.3 via swiftly on
> Ubuntu 22.04 in WSL2: `swift build` and `swift test` pass. The release CLI joined the real vault
> from `rg-passfort-dev` through the Mac's pin file (the Microsoft TLS RSA Root G2 and its
> issuing CA), with the vault under `~`. It pulled every account and shows up in the device list.
> A throwaway `m6-drill` account went both ways: an edit made in the Mac app reached the CLI
> after `sync now`, and an edit made with the CLI reached the app. A pin file holding one bogus
> hash stopped sync. This is the first real pinned handshake through `CLinuxTLS`.

On the Windows PC, in WSL2: build, `swift test`, then join the real vault from
`rg-passfort-dev` with the CLI and pins, and run the two-device drill with the Mac app as the other
device (§13.1). The vault stays in the WSL filesystem (0.7).

**Checkpoint (the milestone's):** an edit on the Mac appears in the WSL2 CLI after `sync`, and the
reverse. A wrong pin stops sync with `pinningFailed`.

## Phase 7 — The WSL2 clipboard (`copy` and `fill`)

> **Built 2026-10-30; the by-hand check on Windows is deferred** (the maintainer's call, the same
> day: CI compiles it and passes `PassFortCLITests` on Linux, which is what the PR could show). `WindowsClipboard` in
> `passfort-cli` (`WindowsClipboard.swift`) follows the route below: `powershell.exe -STA
> -EncodedCommand`, the secret as base64 on stdin, a `DataObject` with the three formats, clear
> by emptying, `explorer.exe` for the URL. `Clipboard` gained `noticesPastes`: false here, so
> `fill` says "paste it, then press Enter" instead of moving on by itself, and `offer` can now
> throw (a PowerShell write can fail). The help text says so. Built before the spike rather than
> after it: the spike's three checks and this phase's checkpoint run together, in one session on
> the PC, against the real backend. If check 2 fails, the stderr warning below goes in then.
> Tests: `PassFortCLITests` (a new test target over the executable) check argv, stdin framing,
> the scripts and the prompts on every platform.

**Depends on:** `passfort-cli copy` and `fill` already built on macOS, against a `Clipboard`
protocol in `passfort-cli` with the `NSPasteboard` backend (concealed type, cleared after the
delay, on Ctrl-C, and only if the clipboard is still ours). This phase adds the second backend; the
commands don't change. Plain Linux outside WSL has no backend in M6: both commands refuse and point
at `get`.

**Which clipboard.** In WSL2 the browser runs on Windows, so the target is the Windows clipboard,
reached through Windows interop. WSL is detected by `WSL_DISTRO_NAME`.

**Why not `clip.exe`.** It is the obvious tool and it fails twice: it reads stdin in the console
code page, so a non-ASCII password arrives mangled unless it is fed UTF-16LE with a BOM, and it
can't mark the copy as sensitive. With Windows clipboard history (Win+V) or cloud clipboard on, the
password would stay in the history after we "clear" it, and could sync to other Windows devices.
That is the Windows form of §3.2 A5, which the concealed type answers on the Mac.

**The route: `powershell.exe` (5.1, STA by default) with a .NET `DataObject`.**

- The secret goes in as base64 on **stdin**, never as an argument: argv is visible in the process
  list on both the Linux and the Windows side. Base64 also sidesteps the console code page.
- The script decodes it and sets `Text` plus the three formats Windows' clipboard history and
  cloud clipboard honour: `ExcludeClipboardContentFromMonitorProcessing` (present), and
  `CanIncludeInClipboardHistory` and `CanUploadToCloudClipboard` (a 4-byte DWORD 0). Then
  `Clipboard::SetDataObject(data, $true)` so the content outlives the process.
- About half a second of PowerShell startup per write. Acceptable for a CLI.
- **Clear** after the delay, and on SIGINT, by setting an empty clipboard. There is no cheap
  "is it still ours" check from WSL like the Mac's `changeCount`, so clearing is unconditional.
  Note that in the command's help.

**`fill` advances on Enter only.** PowerShell sets the clipboard and exits, so nothing is left to
see the paste. The Windows equivalent of the Mac's promise (delayed rendering, `WM_RENDERFORMAT`)
needs a process that stays up with a message loop: a native Windows helper, which is out of scope
(§11: native Windows later and only if needed). Enter already works on every backend, so this costs
nothing but the auto-advance.

**Opening the URL:** `explorer.exe "<url>"`, http and https only (the same check as the Mac).
`cmd.exe /c start` is avoided: cmd parses `&` in the URL. `wslview` is avoided: it needs `wslu`,
no longer installed by default.

**Spike first, on the Windows PC** (a throwaway script, before the backend):

1. A password with non-ASCII characters pastes intact into Edge, Chrome and Notepad.
2. With clipboard history on, the copy never appears in Win+V, and with cloud clipboard on, never
   on a second device.
3. The cleared clipboard pastes nothing.

If 2 fails, the fallback is a warning, not a workaround: read
`HKCU\Software\Microsoft\Clipboard\EnableClipboardHistory` through `reg.exe query` and say on
stderr that the copy will stay in Win+V history. Record the spike's result here, and in §3.2 A5.

**Tests:** the PowerShell script builder and the base64 framing are pure functions, tested on every
platform. The backend itself only runs where `powershell.exe` exists, so it is checked by hand in
the Phase 6 session, not in the `linux` CI job.

**Checkpoint:** in WSL2, `passfort-cli fill <vault> github` opens the login page in the Windows
browser, pastes the username, then (after Enter) the password, and clears the clipboard. Nothing
shows in Win+V. Ctrl-C mid-sequence clears it.

## Phase 8 — Doc sweep

> **Done 2026-10-30** (`architecture.md` rev 24). §11.2 now records what the port replaced and
> how, §11.3 how the CLI is built, §11.5 and §13.1 the tests; the WSL2 clipboard is in §3.2 A5
> and §3.4; §14.21 keeps (c) and (d) open; §15 drops M6 but for the Phase 7 check. §13.2 got the
> `linux` job in rev 23. `development.md` has the Linux loop; `SECURITY.md` the Linux pinning, the
> missing revocation check and memory locking; the README the CLI's requirements and *The CLI on
> Linux and WSL2*. The `m6-spike` branch stays until the maintainer says to delete it.

`architecture.md` (§11, §13.2, §14.21, Appendix A), `development.md` (the Linux loop),
`SECURITY.md` (Linux pinning, the locking allocator), the README's requirements and a short "CLI on
Linux / WSL2" section, and the runbook index. Delete the `m6-spike` branch once the runbook carries
its results (ask first).
