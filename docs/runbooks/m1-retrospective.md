# M1 retrospective — did C++ earn its place?

**Verdict: C++ stays. Proceed to `m2-vault-storage.md`.**

`architecture.md` §12.1: *if more of M1 went into fighting the seam than into the cryptography, drop C++
and reimplement in Swift.* The three questions the runbook asks:

## Interop friction vs. actual cryptography

Roughly **one third friction, two thirds crypto/design**, and the friction was front-loaded and
one-time, not ongoing. The friction, in order of pain:

- the vendored Botan is a *minimized amalgamation* — `#include "botan_all.h"`, not `<botan/*.h>`;
  every phase's first snippet from the runbook had to be corrected for this
- clang nullability (`_Nullable` / `assume_nonnull` vs. `-Wpedantic -Werror -Wnullability-*`) — a real
  rabbit hole in Phases 5–6, settled by annotating **only** the opaque `Session*` / `Mac*` and leaving
  `(pointer, length)` byte inputs unannotated
- `OpaquePointer` is not `Sendable` in this toolchain → `nonisolated(unsafe)` for the actor's handle;
  `ManifestBuilder` crossing the actor boundary → `@unchecked Sendable`
- `pf.KdfParams.salt` (`uint8_t[16]`) imports as a 16-tuple → manual marshaling
- adding headers to the umbrella module did not invalidate Swift's module cache (needed one clean build)

None of that recurred once the pattern was set in Phase 5; Phases 6–10 reused it without new seam
work. The actual thinking went into the AAD layouts (§5.3 header, §5.4 record), the manifest-MAC
streaming shape and its `vault_version`-first ordering, the RFC-9106 KAT (secret + AD, the 5-arg
`hash` overload), and the KDF-parameter DoS the tamper suite caught.

## Did any §6.1 rule break under pressure?

No. All eight held: every boundary function is `noexcept` + `catch (...) -> Status`; errors are the
`int32_t` enum; handles are opaque and freed through the seam; only POD crosses; `pf_bytes_free`
genuinely scrubs (the deferred Phase-1 `Bytes` → `SecureBytes` swap was done in Phase 6 for exactly
this); `import PFCrypto` lives in one module (verified — it fails to compile in `PassFortVault`).
Pragmatic additions that aren't in the rules: a best-effort liveness sentinel on `Session`/`Mac`, and
`internal/Session.hpp` as a shared-but-unexported header (same category as `Bytes.hpp`).

## Is the WASM port (§6.5, M6) still plausible?

Yes, no red flags. The core is the Botan amalgamation (Emscripten-supported) plus ~1.5k lines of our
code that is byte manipulation and Botan factory calls — the only platform touchpoint is
`Botan::system_rng()`, which Emscripten maps to `crypto.getRandomValues`. The seam is POD-only free
functions; `Web/src/crypto/session.ts` mirrors `VaultSession.swift` one-to-one. The frozen
cross-implementation vectors (the HKDF KEK vector in `test_keyring.cpp`, the manifest-MAC vector in
`test_manifest.cpp`) are already the anchors a second implementation checks against.

## Where M1 landed

- The whole §6.2 surface is real, native-tested (KATs / tamper / seam-fuzz, also under ASan+UBSan),
  and driven from Swift through `VaultSession` + `ManifestBuilder`.
- `passfort-cli` does `bench` / `init` / `unlock` / `seal` / `open` with no GUI.
- CI runs `swift` / `native` (plain + sanitizer) / `deps` / `lint` / `secrets` on every push.
