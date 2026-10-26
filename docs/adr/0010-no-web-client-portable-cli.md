# ADR-0010: No web client; a portable CLI reaches the vault where the apps can't be installed

**Status:** Accepted
**Date:** 2026-10-26
**Supersedes:** ADR-0006 (the web client and its WebAssembly crypto core)

## Context

ADR-0006 planned M6, a browser client that runs `PFCrypto` compiled to WebAssembly and speaks the
sync API. It was chosen for a learning goal (`architecture.md` §1.1 goal 7) and as a convenience for
a machine where the Mac or iPhone app can't be installed. With M5 done and the sync API deployed,
the case for it no longer holds:

- **It is the least trusted client.** Whoever serves the page's JavaScript can serve code that
  captures the master password on the next unlock (§3.4, §11.4 of rev 16). ADR-0006 said so itself:
  WebAssembly fixes format correctness and the dependency count, not that. Every mitigation (SRI,
  strict CSP, pinned builds) raises the cost without closing it.
- **It only helps where nothing else can run.** On any Mac or iPhone the native apps are better. The
  one real gap is a machine where they can't be installed, such as a Windows PC.
- **It is the most expensive client to add.** An Emscripten toolchain, a `Web/` tree, a `web` CI
  job, a three-core byte-agreement suite, and a weaker anti-rollback cache (browser storage the
  code-serving origin can wipe, §3.4).

The same gap can be filled by the CLI that already exists. `passfort-cli` does unlock, CRUD, export,
backup and restore, and `sync`, against the same SQLite vault and the same sync engine as the apps.
It is code you built or installed yourself, so nothing a server sends can change what it does. What
stops it running on Linux or Windows is a short list of Apple-only code, found by reading the
package on 2026-10-26:

| Where | Apple-only use |
|---|---|
| `PassFortVault/Sync/PinnedTransport.swift` | `Security` (`SecTrust`) for SPKI pinning, `CryptoKit` for the hash, `os` (`OSAllocatedUnfairLock`) |
| `PassFortVault/OneTimeCode.swift` | `CryptoKit` HMAC for RFC 6238 codes |
| `PFCrypto/vendor/botan/` | the amalgamation is configured by `build_botan.sh` for `--os=macos --cpu=arm64` |
| `Package.swift` | `platforms: [.macOS(.v14)]` only |
| GRDB | believed to support Linux; native Windows support not verified |

### What "Static Web Apps" is in this project

This ADR is the right place to say it plainly, because the name suggests a website. **Azure Static
Web Apps is the host of the sync API and nothing else.** Its Free tier bundles managed Functions, a
managed TLS certificate and a stable hostname at $0 (ADR-0005). The Mac app, the iPhone app and the
CLI all call the Functions under `/api/v1`, and no client is served from it. The `site/` folder in
`PassFortCloud` is a one-line placeholder page plus `staticwebapp.config.json`. Read "SWA-hosted" as
"the Azure Functions API endpoint". Dropping the web client changes nothing about the backend.

## Decision

1. **The web client is withdrawn.** M6 as ADR-0006 defined it is not built: no `Web/`, no
   `pfcrypto.wasm`, no `build_wasm.sh`, no Emscripten, no `web` CI job. `architecture.md` §11 is
   rewritten for the CLI, learning goal 7 and adversary A7 are withdrawn, and ADR-0006 is superseded.
2. **M6 becomes the portable CLI, Linux first.** `passfort-cli` builds and passes the package's
   tests on Linux (x86_64 first), and runs on a Windows machine through WSL2 from the day the Linux
   build works. The commands, the vault format, the sync protocol and the seam do not change. The port
   replaces the Apple-only code above and nothing else.
3. **Native Windows is a later, optional step,** taken only if WSL turns out not to be enough. It
   would need its own Botan amalgamation, a Windows build of Swift with C++ interop, and a check
   that GRDB builds there. None of that is started or planned in detail.
4. **The backend is unchanged.** No API, contract, schema or format change. `PassFortCloud` is not
   touched by this ADR. Its placeholder page still says "The web client arrives in M6" and should be
   reworded the next time that repository is deployed.
5. **The open questions go in the M6 runbook's Phase 0 spike**, not in this ADR:
   how Linux pins the sync server's key (a `URLSession` server-trust delegate may not exist in
   `swift-corelibs-foundation`; libcurl's pinned-public-key option is the likely fit), whether the
   `CryptoKit` uses move to `swift-crypto` (a new first-party dependency, its own reviewed commit
   with its transitive cost stated, per the minimal-dependencies rule) or to something smaller,
   how the second Botan amalgamation is laid out (an ADR-0001 amendment), and whether Botan's
   locking allocator works under the default `RLIMIT_MEMLOCK`.

## Consequences

- **A smaller system to build and defend.** No second crypto host, no browser trust tier, no
  CSP / SRI / reproducible-bundle work. Adversary A7 and three §3.4 limitations go away.
- **The §12.1 exit criterion gets simpler.** Only Swift hosts the core now, in the apps and the CLI.
  If C++ is ever dropped, nothing else moves with it.
- **The seam rules stay as they are.** `noexcept`, status codes, POD only and `(pointer, size)` bytes
  were partly justified by a JS↔WASM boundary. They cost nothing and still suit Swift.
- **The CLI is the same trust tier as the native apps.** The code is what you built or installed,
  and the server ships none of it. The anti-rollback mark is the same `<db>.hw` file next to the
  database. The CLI does have its own exposure: it prints secrets on request, so they can end up in
  terminal scrollback, and a machine you don't control sees the plaintext of a vault you open on it.
- **There is no zero-install access.** A machine needs a Linux or WSL environment, the Swift
  toolchain (or a binary built elsewhere) and a copy of the vault via sync. That is a deliberate
  trade for the trust level.
- **Cross-host agreement is still tested,** between macOS and Linux, by opening fixture vaults
  written on one on the other. That replaces the "three cores agree" rule of ADR-0006.
- **M7 is unaffected.** It never depended on M6.

## Alternatives considered

- **Keep the web client as planned (ADR-0006).** Rejected for the reasons in Context. If a browser
  client is ever wanted, the form to build is one whose code is not delivered by the server: a
  browser extension, or a single-file bundle verified against a tagged release and opened from
  disk. That still needs the WASM core, so it is not cheaper.
- **A JavaScript reimplementation of the crypto in a web client.** ADR-0006's reasons still stand:
  a permanent byte-compatibility obligation between two codebases and more dependencies.
- **A new CLI written in C++ only.** Rejected: the storage layer and the sync engine are Swift
  (ADR-0004), so it would be a second implementation of both. That is the objection ADR-0006 raised
  against JavaScript.
- **Windows-native first.** Rejected: it has the most unknowns (Swift with C++ interop on Windows,
  GRDB, a third Botan configuration) for the same end result that WSL gives sooner.
- **Server-side decryption.** Still not an option: the server would see plaintext.
- **Move the API off Static Web Apps now that no web client needs it.** Not worth it. The deployed
  backend works and costs $0, and a standalone Function App brings storage, identity and Key Vault
  questions that SWA's managed Functions sidestep (`architecture.md` §10.1).
