# ADR-0006: The web client runs the crypto core as WebAssembly

**Status:** Accepted
**Date:** 2026-08-28

## Context

The web client (architecture §11) does CRUD over the same vault as the native app. A password
manager cannot decrypt server-side without handing the server plaintext and, effectively, the
master password — so the browser must run key derivation, the key hierarchy, record seal/open,
and the manifest MAC itself. That is the same work `PFCrypto` already does in C++.

There are two ways to get it into a browser:

1. **Reimplement in JavaScript** — WebCrypto for the AEAD (it has no XChaCha20-Poly1305, so a
   JS/WASM ChaCha or a polyfill), `argon2-browser` for Argon2id, plus HKDF and the
   canonical-encoding logic by hand. Every one of these must stay byte-for-byte compatible with
   the C++ core forever, or a vault written on the desktop won't open in the browser.
2. **Compile the existing core to WebAssembly** with Emscripten, over the Botan amalgamation that
   ADR-0001 already produces.

The project's whole posture is minimal dependencies and one implementation of anything
security-critical. ADR-0004 established that the vault format is a property of the bytes, not the
language, and made the seam (§6) narrow enough that a second host is a transcription job. The
§6.1 rules — noexcept, status codes, opaque handles, POD-only, explicit byte marshalling — were
written for Swift↔C++ but describe a JS↔WASM boundary exactly.

## Decision

The web client gets its cryptography by **compiling `PFCrypto` to `pfcrypto.wasm`** via Emscripten
(`scripts/build_wasm.sh`), driven through the same boundary surface the Swift wrapper uses.

- Boundary functions are exported with `EMSCRIPTEN_KEEPALIVE`; `BytesResult`-shaped structs are
  read out of `HEAPU8`; opaque handles are the pointers Emscripten returns. No §6.1 rule changes.
- `Web/src/crypto/session.ts` is the line-for-line analogue of `VaultSession.swift`, including the
  `consume(_:)` helper of §6.3.
- Argon2id runs in a Web Worker, never the UI thread — the browser analogue of the `VaultSession`
  actor (§6.4).
- The build is single-threaded unless cross-origin isolation (`COOP`/`COEP`) is in place for
  pthreads. A web-safe KDF memory ceiling is documented, because a 512 MiB Argon2 can OOM a mobile
  tab (§11.2); a vault whose header exceeds it is opened on the desktop app, never silently
  weakened.
- There is no JavaScript reimplementation of any crypto primitive. WebCrypto is used only for
  non-vault incidentals (`getRandomValues`); TLS is the browser's.

## Consequences

- **One implementation of the vault format**, consumed by three hosts (Swift, browser, CLI). A
  format change is made once in C++ and recompiled, not ported.
- **No runtime crypto dependency** is added to the web client — the WASM blob is our own code plus
  Botan, which we already vendor.
- **The seam design pays off a second time.** The narrowness that ADR-0002/0004 justified for
  interop is what makes the browser port cheap; this is concrete evidence for those decisions.
- **Testing gains a rule:** the §13 seam fuzz suite and the primitive KATs run against the WASM
  build too, and all three cores must agree byte-for-byte on the same vectors.
- **Cost:** Emscripten in the toolchain (build-time only), a ~300–500 KB WASM download (cached
  after first load), and the cross-origin-isolation / memory-ceiling wrinkles above.
- **The web client cannot page-lock memory** — no browser primitive exists — so Botan's locking
  allocator is a no-op there. Recorded in §3.4; auto-lock and session teardown are the only
  mitigations.
- **This binds the web client to the §12.1 exit criterion.** If C++ is dropped for Swift, the
  browser port goes with it — SwiftWasm exists but is a heavier toolchain, and M6 is re-scoped at
  that point rather than now.
- **It does not change the web client's trust tier.** Running our own audited core in the browser
  does nothing about the fact that the server ships the page that loads it (§11.4, A2/A7). WASM is
  about format correctness and dependency count, not about the load-bearing limitation.

## Alternatives considered

- **JavaScript / WebCrypto reimplementation.** More conventional, and the primitives are
  individually fine. Rejected: it is exactly the reimplementation §12.1 treats as a cost, it
  multiplies the dependency count (Argon2, ChaCha, HKDF helpers) the project works to keep near
  zero, and it creates a permanent byte-compatibility obligation between two codebases.
- **A subset in JS, the hard parts in WASM** (Argon2 in WASM, framing and encoding in JS).
  Rejected: worst of both — still two implementations of the format's canonical encoding, still a
  compatibility burden.
- **Server-side decryption with a session key.** Rejected outright: it hands the server plaintext
  and defeats the entire threat model. Not a real option for a password manager.
- **No web client at all.** The safe choice, and the one rev-3 implied. Rejected because the
  browser E2EE exercise is a stated learning goal (§1.1 goal 7), and the trust limitations are
  worth understanding by building — as long as they are documented honestly (§11.4).
