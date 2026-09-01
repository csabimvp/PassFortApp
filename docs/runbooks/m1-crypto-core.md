# M1 — Crypto core + seam

**Status:** Active. Follow top to bottom. At the end, `passfort-cli` creates a vault, opens a session,
seals and opens a record, and computes the manifest MAC — **all through Swift** — and the RFC
known-answer, tamper, and seam-fuzz suites are green.
**Prerequisite:** `bootstrap.md` complete through Phase 5 (Botan linked, CMake harness live, CI green).
**Spec:** `architecture.md` §5 (crypto design), §6.2 (the surface), §7.4 (`KdfParameters`), §13.1 (tests).

---

## What M1 delivers

`architecture.md` §12: *"Botan amalgamation builds; Argon2id calibrated; keyring, HKDF subkeys,
seal/open, manifest MAC; `PassFortCrypto` actor over the full §6.2 surface. Done when `passfort-cli
seal` / `open` works through Swift; KATs + tamper tests green."*

The whole §6.2 surface, top to bottom:

```
pf_kdf_calibrate(target_ms)                       -> KdfParams        Phase 4
pf_vault_create(password*, len, KdfParams)        -> BytesResult      Phase 5   (header blob)
pf_session_open(header*, len, password*, len)     -> SessionResult    Phase 5   (opaque handle)
pf_session_rewrap(Session*, new_password*, len)   -> BytesResult      Phase 5   (new header)
pf_session_close(Session*)                                            Phase 5
pf_seal(Session*, uuid16*, version, schema, pt*, len)   -> BytesResult    Phase 6
pf_open(Session*, uuid16*, version, schema, sealed*, len) -> BytesResult  Phase 6
pf_mac_init(Session*)                             -> MacResult        Phase 7
pf_mac_update(Mac*, uuid16*, version, sealed*, len) -> Status         Phase 7
pf_mac_finish(Mac*)                               -> BytesResult      Phase 7   (32B)
pf_mac_free(Mac*)                                                     Phase 7
pf_bytes_data / pf_bytes_size / pf_bytes_free                         done (bootstrap Phase 2)
```

**Order matters.** KATs before wrappers (Phase 3), primitives before composition (4 → 5 → 6 → 7),
C++ fully tested natively before the Swift actor wraps it (Phase 8 before 9). You are never more than
one `ctest` away from knowing the layer below you is correct.

---

## Phase 0 — Calibrate expectations, then restructure

`PFCrypto` is currently one file (`boundary/bytes.cpp`) plus two probe functions (`pf_echo`,
`pf_botan_version`). §4 wants four internal areas behind the public facade:

```
Sources/PFCrypto/
├── include/PFCrypto/          # PUBLIC headers — the only thing Swift's clang importer sees
│   ├── PFStatus.hpp           # exists
│   ├── PFBytes.hpp            # exists — trim the probes out at the end of M1
│   ├── PFSession.hpp          # NEW — session lifecycle + seal/open declarations
│   └── PFManifest.hpp         # NEW — streaming MAC declarations
├── internal/                  # NEW — shared C++ headers, NOT exported (not under include/)
│   ├── Bytes.hpp              # the Bytes class definition, so keyring/aead/manifest can all return one
│   ├── Secure.hpp             # SecureBytes = Botan::secure_vector wrapper + scrub
│   └── Canonical.hpp          # fixed-endian field writers for the header codec and AAD
├── boundary/                  # noexcept facade: try/catch, POD marshaling, nothing else
│   ├── bytes.cpp             # pf_bytes_*  (+ pf_echo/pf_botan_version until end of M1)
│   ├── session.cpp          # pf_kdf_calibrate, pf_vault_create, pf_session_*
│   ├── record.cpp           # pf_seal, pf_open
│   └── manifest.cpp         # pf_mac_*
├── keyring/                   # Argon2id, HKDF hierarchy, DEK wrap, header codec
│   ├── kdf.cpp / kdf.hpp
│   ├── hkdf.cpp / hkdf.hpp
│   └── header.cpp / header.hpp
├── aead/                      # record seal/open, AAD construction
│   └── record_crypto.cpp / .hpp
├── manifest/                  # HMAC streaming
│   └── manifest_mac.cpp / .hpp
└── vendor/botan/              # unchanged
```

**Why `internal/` is a sibling of `include/`, not a subdirectory of it.** SwiftPM exports the whole
`include/` tree to dependents' header search path. Anything under it can be `#include`d by — and its
types can leak into — the Swift-facing module. `internal/` sits outside that, added only to
`PFCrypto`'s *own* compile via a header search path, so `Bytes.hpp` / `Secure.hpp` are shared between
`keyring/` and `aead/` but invisible to Swift. This is the §4 rule 1 boundary applied one level down.

### Restructure steps

```bash
cd /Users/csabimvp/dev/projects/PassFortApp/Packages/PassFortKit/Sources/PFCrypto
mkdir -p internal keyring aead manifest
```

Move the `Bytes` class out of `boundary/bytes.cpp` into `internal/Bytes.hpp` (declaration + inline
definition — it is small and every `boundary/*.cpp` needs it):

```cpp
// internal/Bytes.hpp
#pragma once
#include "PFCrypto/PFBytes.hpp"   // for pf::BytesResult, pf::Status
#include "Secure.hpp"
#include <cstdint>
#include <utility>

namespace pf {

// The one owned-buffer type every boundary function returns. Backed by SecureBytes
// so pf_bytes_free is a real scrub (Secure.hpp), not a memset the optimizer drops.
class Bytes {
public:
    explicit Bytes(SecureBytes bytes) : bytes_(std::move(bytes)) {}
    static Bytes copyOf(const uint8_t *p, size_t n) { return Bytes(SecureBytes(p, p + n)); }

    const uint8_t *data() const noexcept { return bytes_.data(); }
    size_t size() const noexcept { return bytes_.size(); }

private:
    SecureBytes bytes_;
};

// pf_bytes_* live in boundary/bytes.cpp and call through to this.

}  // namespace pf
```

Update `Package.swift` — `PFCrypto` needs the `internal/` search path, and (still) `vendor/botan`:

```swift
.target(
    name: "PFCrypto",
    cxxSettings: [
        .headerSearchPath("include"),
        .headerSearchPath("internal"),
        .headerSearchPath("vendor/botan"),
    ]
),
```

SwiftPM compiles every `.cpp` under `Sources/PFCrypto/` automatically, so `keyring/kdf.cpp` etc. join
the build the moment they exist — no target edits per file.

Update `native-tests/CMakeLists.txt` so `pfcrypto_tests` sees the new tree:

```cmake
set(PFCRYPTO ${CMAKE_CURRENT_SOURCE_DIR}/../Packages/PassFortKit/Sources/PFCrypto)

add_executable(pfcrypto_tests
    ${PFCRYPTO}/boundary/bytes.cpp
    ${PFCRYPTO}/boundary/session.cpp
    ${PFCRYPTO}/boundary/record.cpp
    ${PFCRYPTO}/boundary/manifest.cpp
    ${PFCRYPTO}/keyring/kdf.cpp
    ${PFCRYPTO}/keyring/hkdf.cpp
    ${PFCRYPTO}/keyring/header.cpp
    ${PFCRYPTO}/aead/record_crypto.cpp
    ${PFCRYPTO}/manifest/manifest_mac.cpp
    tests/test_bytes.cpp
    tests/test_kat_argon2.cpp
    tests/test_kat_chacha.cpp
    tests/test_kat_hkdf.cpp
    tests/test_header_codec.cpp
    tests/test_seal_open.cpp
    tests/test_tamper.cpp
    tests/test_manifest.cpp
    tests/test_seam_fuzz.cpp)
target_include_directories(pfcrypto_tests PRIVATE
    ${PFCRYPTO}/include ${PFCRYPTO}/internal)
target_compile_options(pfcrypto_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(pfcrypto_tests PRIVATE pf_botan Catch2::Catch2WithMain)
```

**What this block does.** Unlike SwiftPM, which globs every `.cpp` under a target directory, CMake
needs each translation unit named explicitly. `add_executable(pfcrypto_tests …)` lists the `.cpp`
files that compile and link into the test binary. `target_include_directories(… PRIVATE …)` is the set
of `-I` flags for that target — here, the public headers *and* `internal/`, because the tests reach
past the facade to exercise `keyring`/`aead` directly (the sanctioned exception from
`architecture.md` §13). `target_link_libraries` links the prebuilt Botan static lib and Catch2. A file
named here that doesn't exist yet fails `cmake -S … -B …` (the *configure* step), not the build — so:

Add each source and test file to this list **as you create it in the phase below** — don't paste the
whole list before the files exist. It's shown complete here so you can see where you're headed. After
editing `CMakeLists.txt` you must re-run configure (`cmake -S native-tests -B native-tests/build`)
before `cmake --build`; after editing only `.cpp`/`.hpp` files, `cmake --build` alone is enough.

**Checkpoint:** `swift build` and `ctest --test-dir native-tests/build` are still green with the moved
`Bytes` class and the empty new directories. Commit: `Restructure PFCrypto into keyring/aead/manifest
(architecture §4)`.

---

## Phase 1 — `internal/Secure.hpp`: secure memory

Everything secret in M1 lives in `Botan::secure_vector<uint8_t>`. That type is a `std::vector` with a
custom allocator that (a) asks the OS to keep the pages out of swap (`mlock`, best-effort — capped by
`RLIMIT_MEMLOCK`, see `architecture.md` §3.4) and (b) overwrites the memory with zeros before freeing
it. You use it exactly like `std::vector<uint8_t>` — `.data()`, `.size()`, `.push_back`, range
constructors — it just cleans up after itself. `Secure.hpp` is a one-line alias plus a helper so the
rest of the code never has to name Botan directly outside `keyring/`/`aead/`:

```cpp
// internal/Secure.hpp
#pragma once
#include <botan/secmem.h>
#include <cstdint>

namespace pf {

using SecureBytes = Botan::secure_vector<uint8_t>;

// Botan::secure_vector already scrubs on destruction (secure_scrub_memory).
// This is here for buffers you must wipe *before* they go out of scope.
inline void scrub(SecureBytes &b) noexcept {
    if (!b.empty()) Botan::secure_scrub_memory(b.data(), b.size());
}

}  // namespace pf
```

**Why not `std::memset`.** A compiler is allowed to delete a `memset` whose result is never read — the
classic "dead store elimination wipes your key" bug. `Botan::secure_scrub_memory` is written
specifically to be un-elidable. This is also why `internal/Bytes.hpp` is backed by `SecureBytes` and
not `std::vector`: `pf_bytes_free` must genuinely erase decrypted plaintext.

**Checkpoint:** `swift build` green (the header compiles as part of `bytes.cpp`). No test yet — this is
infrastructure.

---

## Phase 2 — `internal/Canonical.hpp`: fixed-layout encoding

The header codec (§5.3) and the AEAD AAD (§5.4) are **byte layouts that three implementations must
agree on** (Swift host, CLI, WASM). Define the field writers once:

```cpp
// internal/Canonical.hpp
#pragma once
#include "Secure.hpp"
#include <cstdint>
#include <cstring>

namespace pf::canon {

// All multi-byte integers in the vault format are BIG-ENDIAN. Pick one and never
// think about it again. (Botan's own serializers are big-endian too — no conflict.)
inline void put_u8 (SecureBytes &o, uint8_t v)  { o.push_back(v); }
inline void put_u16(SecureBytes &o, uint16_t v) { o.push_back(v >> 8); o.push_back(v & 0xFF); }
inline void put_u32(SecureBytes &o, uint32_t v) { for (int s = 24; s >= 0; s -= 8) o.push_back((v >> s) & 0xFF); }
inline void put_u64(SecureBytes &o, uint64_t v) { for (int s = 56; s >= 0; s -= 8) o.push_back((v >> s) & 0xFF); }
inline void put_bytes(SecureBytes &o, const uint8_t *p, size_t n) { o.insert(o.end(), p, p + n); }

// A matching reader with bounds checks lives in header.cpp — it must return
// Status::BadInput on a short buffer, never read past the end.

}  // namespace pf::canon
```

**How the integer writers work.** Each `put_uN` appends the bytes of `v` most-significant first. For
`put_u32`, the loop takes shift amounts `24, 16, 8, 0`; `(v >> s) & 0xFF` isolates one byte at a time,
so `0x01020304` is appended as `01 02 03 04`. `put_u16` is the same idea unrolled. `put_bytes` copies
a raw range in verbatim (fixed-width fields like the 16-byte UUID and the 24-byte nonce). Nothing here
depends on the host's own endianness — the bytes are assembled arithmetically — so a little-endian Mac
and a big-endian machine produce identical output. That's the property that lets the CLI, the app, and
the WASM core seal vaults each other can open.

Add `tests/test_header_codec.cpp` with a round-trip and a truncation test now (the reader lands in
Phase 5, so start with just the writers):

```cpp
TEST_CASE("canon put_u32 is big-endian", "[canon]") {
    pf::SecureBytes o;
    pf::canon::put_u32(o, 0x01020304);
    REQUIRE(o == pf::SecureBytes{0x01, 0x02, 0x03, 0x04});
}
```

**Why big-endian, stated once:** network byte order, it's what most format specs use, and it makes hex
dumps of a vault header read left-to-right. The choice is arbitrary but it must be *written down* — put
a one-liner in `architecture.md` §5.3 ("all integers big-endian") when you land this.

**Checkpoint:** `ctest -R canon` passes. Commit: `Add canonical big-endian field encoders`.

---

## Phase 3 — Known-answer tests, before any wrapper

`architecture.md` §13.1: *"Never trust a wrapper you haven't KAT'd."* Prove the Botan module set from
ADR-0001 actually computes the right bytes, using vectors from the RFCs, **calling Botan directly** —
not your not-yet-written wrappers.

**Botan's factory pattern, since every snippet below uses it.** You don't `#include` a header per
algorithm; you ask for one by name from a factory (`PasswordHashFamily`, `AEAD_Mode`, `KDF`, `MAC`)
and get back a polymorphic object you drive through a small interface. The `_or_throw` /
`create_or_throw` variants throw a `Botan::Exception` on an unknown name or bad parameters instead of
returning a null pointer — fine in a test (Catch2 reports the throw), and in the real wrappers the
`noexcept` facade's `catch (...)` turns it into `Status::Internal`. `Botan::hex_decode` /
`hex_encode` convert between hex strings and byte vectors, so a test can paste an RFC vector verbatim.

### `tests/test_kat_argon2.cpp` — RFC 9106

RFC 9106 §5.3 gives an Argon2id test vector (password/salt/secret/ad all fixed, `m=32, t=3, p=4`,
32-byte tag → `0d 64 0d f5 8d 78 76 6c 08 c0 37 a3 4a 8b 53 c9 d0 1e f0 45 2d 75 b6 5e b5 25 20 e9 6b 01 e6 59`).

```cpp
#include <catch2/catch_test_macros.hpp>
#include <botan/pwdhash.h>
#include <botan/hex.h>
#include <vector>

TEST_CASE("Argon2id matches RFC 9106 section 5.3", "[kat][argon2]") {
    auto fam = Botan::PasswordHashFamily::create_or_throw("Argon2id");
    auto ph  = fam->from_params(/*M=*/32, /*t=*/3, /*p=*/4);   // M in KiB

    const auto pass = Botan::hex_decode("0101010101010101010101010101010101010101010101010101010101010101");
    const auto salt = Botan::hex_decode("02020202020202020202020202020202");
    // NOTE: RFC 9106's vector also feeds a "secret" (K) and "associated data" (X).
    // Botan's PasswordHash interface does not take those. Use the reduced vector
    // (no secret, no AD) from a source that publishes one for that interface, or
    // KAT via Botan's `argon2()` low-level function which does accept them.

    std::vector<uint8_t> out(32);
    ph->hash(out, std::string(pass.begin(), pass.end()), salt);
    REQUIRE(Botan::hex_encode(out) == /* expected */ "...");
}
```

**Read the note in that snippet before you copy it.** The RFC vector uses the full Argon2 input set
(secret key + associated data); Botan's high-level `PasswordHash` interface omits both. Either KAT
against `Botan::argon2(...)` (the low-level function, which takes all inputs) or use a published vector
for the reduced input set. Getting this exactly right *is* the point of the phase — a KDF you "think"
matches is worthless.

### `tests/test_kat_chacha.cpp` — RFC 8439

RFC 8439 §2.8.2 gives a ChaCha20-Poly1305 AEAD vector (key, 96-bit nonce, AAD, plaintext →
ciphertext + tag). Botan's XChaCha uses a 192-bit nonce, so this vector tests the **underlying**
ChaCha20-Poly1305, which is what you want to KAT — XChaCha is `HChaCha20` + ChaCha20-Poly1305 and Botan
composes it for you.

```cpp
auto enc = Botan::AEAD_Mode::create_or_throw("ChaCha20Poly1305", Botan::Cipher_Dir::Encryption);
enc->set_key(key);
enc->set_associated_data(aad.data(), aad.size());
enc->start(nonce_96);
Botan::secure_vector<uint8_t> buf(pt.begin(), pt.end());
enc->finish(buf);                 // buf is now ciphertext ‖ 16-byte tag
REQUIRE(Botan::hex_encode(buf) == expected_ct_and_tag);
```

**Botan's AEAD protocol.** One object handles both directions; `Cipher_Dir::Encryption` /
`Decryption` picks. Then it's always the same four calls: `set_key`, `set_associated_data` (the AAD —
authenticated but not encrypted), `start(nonce)`, and `finish(buffer)` which works **in place** on a
`secure_vector`. On encrypt, `finish` appends the 16-byte Poly1305 tag. On decrypt, `finish` verifies
the tag and *throws* `Botan::Invalid_Authentication_Tag` if it doesn't match — which is why the wrong
password, a flipped ciphertext bit, and a tampered AAD all land in the same `catch` and all return
`AuthFailed` (§13.1, no oracle). XChaCha20-Poly1305 is the same interface with a 24-byte nonce; Botan
does the `HChaCha20` nonce-extension step internally.

Also add an **XChaCha20-Poly1305** round-trip with a 24-byte nonce (no published RFC vector, but
libsodium publishes one — or just assert encrypt-then-decrypt returns the plaintext and a 24-byte
nonce is accepted). `architecture.md` §4.1 already confirmed Botan reports valid nonce lengths
`{8, 12, 24}` for `ChaCha20Poly1305`.

### `tests/test_kat_hkdf.cpp` — RFC 5869

RFC 5869 appendix A gives seven HKDF-SHA-256 / SHA-1 test cases (IKM, salt, info → PRK, OKM). KAT the
full extract-then-expand:

```cpp
auto hkdf = Botan::KDF::create_or_throw("HKDF(SHA-256)");
auto okm  = hkdf->derive_key(42, ikm.data(), ikm.size(), salt.data(), salt.size(), info.data(), info.size());
REQUIRE(Botan::hex_encode(okm) == rfc5869_A1_okm);
```

**What `derive_key` does.** HKDF is two steps: *extract* — `HMAC(salt, IKM)` produces a
fixed-length pseudorandom key (PRK) — and *expand* — `PRK` plus the `info` label and a length produce
that many output bytes. `derive_key(len, ikm, salt, info)` runs both and hands back `len` bytes. The
`info` argument is the domain separator: same IKM, different `info` → unrelated keys. That's the whole
mechanism behind the §5.1 hierarchy — one Argon2 result, expanded with `"pf-kek-v1"`, `"pf-rec-v1"`,
`"pf-mft-v1"` into keys that can't be derived from one another.

**Checkpoint:** `ctest -R kat` — all three suites green. This is the moment you know Botan is wired
correctly. Commit: `Add RFC 9106 / 8439 / 5869 known-answer tests (architecture §13.1)`.

---

## Phase 4 — `keyring/`: Argon2id + the HKDF hierarchy

Now the wrappers, KAT'd primitives underneath them.

### `keyring/kdf.{hpp,cpp}` — Argon2id + calibration

```cpp
// keyring/kdf.hpp
#pragma once
#include "Secure.hpp"
#include <cstdint>

namespace pf::keyring {

struct KdfParams {                 // POD — this is what crosses the seam (§7.4)
    uint8_t  kdf_id = 1;           // 1 = argon2id
    uint32_t m_kib  = 0;
    uint32_t t      = 0;
    uint32_t p      = 0;
    uint8_t  salt[16] = {};
};

// Argon2id(password, params.salt) -> 64 bytes. The 64 feeds HKDF (hkdf.hpp).
SecureBytes argon2id_64(const uint8_t *pw, size_t pw_len, const KdfParams &params);

// Binary-search m_kib for ~target_ms on THIS machine. t/p fixed at 3/4 (§5.2).
KdfParams calibrate(uint32_t target_ms);

}  // namespace pf::keyring
```

- Starting point `m = 512 MiB, t = 3, p = 4` (§5.2). Calibration walks `m` (memory-hardness beats
  iteration count against GPUs), clamps to `[64 MiB, 4 GiB]`, and fills a fresh random 16-byte `salt`
  from `Botan::system_rng()` — Botan's handle to the OS CSPRNG (`getentropy`/`/dev/urandom`), the same
  source you use for record nonces.
- **How `calibrate` works.** Run `argon2id_64` on a throwaway password at a candidate `m`, time it
  with `std::chrono::steady_clock`. Too fast → raise `m` and retry; too slow → lower it. A binary
  search over the clamped range converges in ~5–6 trials (each trial is one full Argon2 run, so the
  whole thing takes a few seconds). The result is stored in the vault header so a vault made on a fast
  machine still opens on a slow one at the *stored* cost, not a re-measured one — that's why the
  parameters have to travel with the data (§5.2).
- `argon2id_64` produces **64 bytes**, not 32 — the key hierarchy (§5.1) HKDF-Expands those 64 into KEK
  and `auth_secret` with domain-separating `info` strings.

### `keyring/hkdf.{hpp,cpp}` — the subkey tree

```cpp
namespace pf::keyring {

struct RootKeys {                  // lives inside the Session handle; scrubbed on close
    SecureBytes kek;               // 32B — HKDF-Expand(argon64, info="pf-kek-v1")
    SecureBytes auth_secret;       // 32B — HKDF-Expand(argon64, info="pf-auth-v1"); sync only (M5)
};

struct DekSubkeys {                // derived from the unwrapped DEK
    SecureBytes k_record;          // HKDF(dek, info="pf-rec-v1")  — record AEAD
    SecureBytes k_index;           // HKDF(dek, info="pf-idx-v1")  — blind indexes (M5)
    SecureBytes k_manifest;        // HKDF(dek, info="pf-mft-v1")  — anti-rollback MAC
};

RootKeys   derive_root(const SecureBytes &argon64);
DekSubkeys derive_dek_subkeys(const SecureBytes &dek);

}  // namespace pf::keyring
```

**Pin the `info` strings in `architecture.md` §5.1** the first time you write them — they are part of
the on-disk format (a vault sealed with `info="pf-rec-v1"` can only be opened with the same string).
Include a version suffix so a future rotation is expressible.

**Why derive `auth_secret` from the same Argon2 run** (§5.1): one expensive KDF pass, two
domain-separated outputs. The KEK never leaves the device; `auth_secret` is the only thing a server
ever sees. Write up the caveat from §5.1 — this makes the server's stored verifier offline-crackable at
Argon2 cost, which a PAKE (OPAQUE/SRP, deferred past M5) would avoid.

**Checkpoint:** unit tests in `tests/test_kat_hkdf.cpp` (extend it) asserting the same `argon64` +
`info` always yields the same subkey, and different `info` yields different subkeys. Commit:
`keyring: Argon2id calibration + HKDF key hierarchy (architecture §5.1-5.2)`.

---

## Phase 5 — `keyring/header.*` + the session lifecycle

### The header codec

`keyring/header.{hpp,cpp}` encodes and decodes the §5.3 layout. "Wrapping" the DEK just means
encrypting it: `wrapped_dek = XChaCha20-Poly1305(KEK, wrap_nonce, DEK, aad = all preceding header
fields)`. Feeding every earlier field in as AAD (§5.3) means the tag also authenticates the KDF
parameters — so an attacker who edits the stored header to say `m = 8 KiB` (cheap to crack) gets a tag
mismatch and `AuthFailed`, not a weakened vault. `header.cpp`:

1. builds the plaintext field bytes with `canon::put_*`,
2. derives the KEK (Argon2id on the password + `kdf_salt`, then HKDF `info="pf-kek-v1"`),
3. runs the AEAD wrap of the 32-byte DEK with those field bytes as AAD,
4. appends `wrap_nonce ‖ wrapped_dek ‖ 16-byte tag`.

Decode reverses it: parse the fields, re-derive the KEK from the supplied password, AEAD-*open* the
slot. A wrong password derives a wrong KEK → the tag check fails → `Status::AuthFailed`, byte-identical
to the response for a corrupt header (§13.1).

```
magic          "PFV\x01"   4B
format_version u16          -> 1
vault_uuid     16B
kdf_id         u8
kdf_m_kib      u32
kdf_t          u32
kdf_p          u32
kdf_salt       16B
wrap_alg       u8           -> 1 (XChaCha20-Poly1305)
slot_count     u8           -> see the decision below
wrap_nonce     24B          } slot 0 (password)
wrapped_dek    32B + 16B tag}
[wrap_nonce    24B          } slot 1 (recovery key) — only if slot_count == 2
 wrapped_dek   32B + 16B tag]
created_at     i64
```

> **Decision to make now: recovery slot in M1 or M2.** §5.6 says the recovery key ships *in M2*. But
> adding a second `wrapped_dek` slot later is a **format change** — an ADR plus a re-seal migration
> (`architecture.md` §8.2, §5.4). No vault with real data exists yet, so the cheap move is to define
> `format_version = 1` **with `slot_count` already in the layout** (M1 writes `slot_count = 1`), so M2
> only has to fill slot 1 — no version bump, no migration. The alternative (M1 header has no slot
> concept, M2 bumps to `format_version = 2`) is more faithful to "one milestone at a time" but costs a
> migration for a format that never shipped. **Recommendation: build `slot_count` in now.** Record
> whichever you pick in `architecture.md` §5.3.

### `include/PFCrypto/PFSession.hpp` — the public declarations

```cpp
#pragma once
#include "PFStatus.hpp"
#include "PFBytes.hpp"
#include <cstdint>

namespace pf {

class Session;                                   // opaque; defined in keyring/session_impl.cpp
struct SessionResult { Session *_Nullable handle; Status status; };

struct KdfParams {                                // POD mirror of keyring::KdfParams
    int32_t  kdf_id;
    uint32_t m_kib, t, p;
    uint8_t  salt[16];
};
struct KdfResult { KdfParams params; Status status; };

KdfResult    pf_kdf_calibrate(uint32_t target_ms) noexcept;
BytesResult  pf_vault_create(const uint8_t *pw, size_t pw_len, KdfParams params) noexcept;
SessionResult pf_session_open(const uint8_t *header, size_t header_len,
                              const uint8_t *pw, size_t pw_len) noexcept;
BytesResult  pf_session_rewrap(Session *s, const uint8_t *new_pw, size_t new_pw_len) noexcept;
void         pf_session_close(Session *_Nullable s) noexcept;   // zeroizes RootKeys + DekSubkeys

}  // namespace pf
```

The `Session` object holds `RootKeys`, the unwrapped `DEK`, and `DekSubkeys` — all `SecureBytes`.
`pf_session_close` scrubs every one and `delete`s. `pf_session_open` on a wrong password returns
`{nullptr, AuthFailed}` — **identical** to a corrupt header, no oracle (§13.1).

**The `_Nullable` markers matter.** They're clang nullability annotations. Swift imports
`Session* _Nullable` as an optional `OpaquePointer?` and `Session* _Nonnull` as a non-optional
`OpaquePointer`, so `SessionResult.handle` forces a `guard let` on the Swift side and
`pf_session_close`'s parameter is allowed to be nil. Leave them off and Swift imports every pointer as
an implicitly-unwrapped optional — no compile-time nil check, exactly the safety you're trying to keep.
The pattern: results are `_Nullable` (a failed call returns nil), `close`/`free` parameters are
`_Nullable` (calling them on nil is a documented no-op), everything else is `_Nonnull`.

### `boundary/session.cpp` — the facade

Each function: `noexcept`, `try { … } catch (...) { return {…, Status::Internal}; }`, POD in / POD or
opaque handle out. No `pf::keyring` type appears in `PFSession.hpp` — the boundary translates.

**Checkpoint:** `tests/test_header_codec.cpp` — round-trips a header, opens it with the right password,
fails `AuthFailed` with a wrong one, fails `AuthFailed` on a header with one flipped byte, `BadInput`
on a 3-byte buffer. `pf_session_rewrap` produces a header the *new* password opens and the old one does
not, and the DEK is unchanged (seal with session A, open with session B-after-rewrap). Commit:
`keyring: vault header codec + session open/rewrap (architecture §5.3)`.

---

## Phase 6 — `aead/`: record seal / open

### `aead/record_crypto.{hpp,cpp}`

```cpp
namespace pf::aead {

// AAD is assembled HERE (§5.4) so its layout is defined in exactly one place:
//   aad = vault_uuid(16) ‖ record_uuid(16) ‖ version(u64 BE) ‖ schema(u16 BE)
SecureBytes seal(const SecureBytes &k_record,
                 const uint8_t vault_uuid[16], const uint8_t record_uuid[16],
                 uint64_t version, uint16_t schema,
                 const uint8_t *plaintext, size_t pt_len);   // -> nonce ‖ ct ‖ tag

SecureBytes open(const SecureBytes &k_record,
                 const uint8_t vault_uuid[16], const uint8_t record_uuid[16],
                 uint64_t version, uint16_t schema,
                 const uint8_t *sealed, size_t sealed_len);   // -> plaintext, or throws
}
```

- `nonce = 24 random bytes` from `Botan::system_rng()` per seal (§5.4). Never a counter — multi-device
  writes have no authoritative counter, and a random 192-bit nonce has no birthday-bound problem.
- `open` throws inside C++ on tag failure; `boundary/record.cpp` catches → `Status::AuthFailed`.
- The `vault_uuid` comes from the session (decoded from the header); Swift passes only `record_uuid`,
  `version`, `schema`. Confirm the boundary signature matches §6.2:
  `pf_seal(Session*, uuid16*, version, schema, plaintext*, len)`.

### `boundary/record.cpp`

`pf_seal` / `pf_open`, same facade discipline. `pf_open` on a closed session → `Status::Locked`.

**Checkpoint:** `tests/test_seal_open.cpp` — seal then open returns the exact plaintext; open with the
wrong `record_uuid` / wrong `version` / wrong `schema` → `AuthFailed` (the AAD binding from §5.4 in
action); empty plaintext seals and opens; a 1 MiB plaintext round-trips. Commit: `aead: record
seal/open with AAD-bound identity (architecture §5.4)`.

---

## Phase 7 — `manifest/`: the streaming anti-rollback MAC

`architecture.md` §5.5 — *"the part most hobby password managers get wrong, and the most instructive
thing in the whole design."*

```
manifest_mac = HMAC-SHA-256(k_manifest,
                 vault_version(u64) ‖ Σ_sorted-by-uuid( uuid ‖ version ‖ SHA-256(ciphertext) ))
```

**What "streaming" means here.** An HMAC doesn't need all its input at once — Botan's `MAC` object
takes `update(bytes)` calls one after another and only produces the tag at `final()`. So instead of one
seam call that would need every sealed blob copied into C++ at once (and would put the iteration logic
in C++), Swift walks its own rows in `uuid` order and makes one `pf_mac_update` call per row.
`k_manifest` stays inside the `Mac` handle the whole time; C++ does the hashing, Swift decides the
order. `pf_mac_init` creates the handle and seeds the HMAC with `k_manifest`; `pf_mac_update` folds in
one row; `pf_mac_finish` folds in `vault_version` and returns the 32-byte tag; `pf_mac_free` releases
the handle.

`k_manifest` never leaves C++, which is what forces this shape:

```cpp
// include/PFCrypto/PFManifest.hpp
namespace pf {
class Mac;                                        // opaque
struct MacResult { Mac *_Nullable handle; Status status; };

MacResult   pf_mac_init(Session *s) noexcept;                 // seeds HMAC with k_manifest
Status      pf_mac_update(Mac *m, const uint8_t uuid[16],
                          uint64_t version, const uint8_t *sealed, size_t len) noexcept;
BytesResult pf_mac_finish(Mac *m) noexcept;                   // 32B; also folds in vault_version
void        pf_mac_free(Mac *_Nullable m) noexcept;
}
```

- **Swift decides iteration order** (UUID-sorted), C++ does the hashing. `pf_mac_update` computes
  `SHA-256(sealed)` internally and feeds `uuid ‖ version ‖ that_hash` into the running HMAC.
- `vault_version` is folded in at `pf_mac_finish` (or passed to `pf_mac_init` — pick one and document
  it). Its high-water mark is cached outside the vault (Keychain in M4; a sidecar file for the M2 CLI)
  so a whole-file rollback to an internally-consistent older DB is still caught.
- `pf_mac_update` after `pf_mac_finish` → `Status::BadInput`. `pf_mac_free` is mandatory (opaque owned
  memory, §6.1 rule 7).

**Checkpoint:** `tests/test_manifest.cpp` — same rows in the same order → same MAC; reorder the
`pf_mac_update` calls → **different** MAC unless Swift sorts (this is the test that proves ordering
matters); drop a row → different MAC; bump `vault_version` → different MAC. Commit: `manifest:
streaming HMAC-SHA-256 anti-rollback MAC (architecture §5.5)`.

---

## Phase 8 — Tamper + seam-fuzz suites

These are non-negotiable per §13.1 and they gate everything after.

### `tests/test_tamper.cpp`

For a sealed record and a valid header, in a loop over every byte offset: flip one bit, assert the
corresponding `open` / `pf_session_open` returns **`AuthFailed`** — not a crash, not success, not a
different error code. Cover: nonce region, ciphertext region, tag region, and (separately) each AAD
input (`record_uuid`, `version`, `schema`) and each header field.

### `tests/test_seam_fuzz.cpp`

Every boundary function, hammered with:

| Input | Expected |
|---|---|
| `nullptr` data with non-zero len | `BadInput` |
| zero len (valid for some, e.g. empty plaintext) | `Ok` or `BadInput` per function — assert which, don't crash |
| `SIZE_MAX` len | `BadInput`, no allocation attempt |
| a `Session*` / `Mac*` that was already `close`d / `free`d | `Locked` / `BadInput`, never use-after-free |
| double `pf_session_close` / `pf_bytes_free` | no-op, no double-free |
| a `Bytes*` from the wrong function passed to the wrong free | out of scope — the type system can't catch this in C, note it |

Run under ASan/UBSan (the `cpp.md` debug default): `cmake -S native-tests -B native-tests/build
-DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined"`.

**What the sanitizers do.** `-fsanitize=address` (ASan) instruments every load and store to detect
heap/stack buffer overflows, use-after-free, and leaks at the moment they happen — instead of "works
on my machine, corrupts memory on CI". `-fsanitize=undefined` (UBSan) traps signed-integer overflow,
shifts past the type width, null-pointer dereference, and misaligned access. Both roughly double
run time and memory, so they're a debug-only build, not the default — but a fuzz suite is exactly
where they pay off. A sanitizer report is a test failure even if the assertions passed.

**Checkpoint:** `ctest --test-dir native-tests/build --output-on-failure` all green, and green again
under the sanitizer build. Commit each suite with the code it exercises if a bug turns up
(`git-and-commits.md`). Otherwise: `Add tamper + seam-fuzz suites (architecture §13.1)`.

---

## Phase 9 — `PassFortCrypto`: the Swift actor over the whole surface

Now — and only now — wrap the C++ that native tests have proven correct.

```
Sources/PassFortCrypto/
├── PassFortError.swift    # exists — extend the enum if M1 surfaced new Status cases
├── Seam.swift             # exists — keep consume(_:); add a consume for SessionResult/MacResult/KdfResult
├── KdfParameters.swift    # NEW — the Sendable Swift view (§7.4); from/to the POD pf.KdfParams
├── VaultSession.swift     # NEW — actor; owns the Session* handle
└── ManifestBuilder.swift  # NEW — wraps pf_mac_init/update/finish/free
```

### `VaultSession.swift`

```swift
import Foundation
internal import PFCrypto

/// Owns the opaque C++ session handle. `actor` because Argon2id blocks ~1s and the
/// C++ session is single-owner / not thread-safe by design (§6.4).
public actor VaultSession {
    private let handle: OpaquePointer            // pf.Session*
    // no init from outside — use the static factories

    public static func create(password: Data, params: KdfParameters) throws -> Data { … }  // pf_vault_create
    public static func open(header: Data, password: Data) throws -> VaultSession { … }      // pf_session_open

    public func seal(recordID: UUID, version: UInt64, schema: UInt16, plaintext: Data) throws -> Data
    public func open(recordID: UUID, version: UInt64, schema: UInt16, sealed: Data) throws -> Data
    public func rewrap(newPassword: Data) throws -> Data
    public func manifestBuilder() throws -> ManifestBuilder

    deinit { pf.pf_session_close(handle) }       // scrubs keys
}
```

**Why `actor`.** An `actor` is a reference type that serializes access to its own mutable state: the
runtime guarantees only one task executes its methods at a time, so the C++ session handle — which is
deliberately not thread-safe, one owner, no locks (§6.4) — can't be raced. Callers from outside hop
onto the actor's executor, which is why the methods are `await`ed at the call site (`try await
session.seal(...)`). Argon2id at ~512 MiB blocks for the better part of a second; running that on an
actor (never `@MainActor`) keeps it off the UI thread for free.

**`deinit`** runs when the last reference to the `VaultSession` drops. `pf_session_close` scrubs
`RootKeys`/`DEK`/`DekSubkeys` and frees the handle there. If you need the keys gone at a *precise*
moment (auto-lock, §12 M3) add an explicit `close()` and null the handle — `deinit` timing isn't
guaranteed to be immediate.

- `import PFCrypto` still appears **only in this module**. Library evolution
  (`bootstrap.md` Phase 2 fix) keeps the interop flag from going viral — verify that guardrail still
  holds after adding these files (`import PFCrypto` in `PassFortVault` must still fail to compile).
- Every `pf.Status` maps through `PassFortError`. Both wrong-password and tamper surface as
  `PassFortError.authFailed` — the Swift API is not an oracle either.
- `UUID` → `uuid16*`: a Swift `UUID`'s `.uuid` property is a 16-tuple of `UInt8` in big-endian
  (RFC 4122) order. `withUnsafeBytes(of: uuid.uuid) { $0.baseAddress }` hands C a pointer to those 16
  bytes, valid for the closure body — that's the `uuid16*` the seam wants, no copy, no byte-swap.

### `passfort-cli` smoke

Extend `main.swift` (still no argument parser — that's Phase 10) to run the full round trip and print
`M1 seam OK`:

```swift
let params = try VaultSession.calibrate(targetMs: 500)
let header = try VaultSession.create(password: Data("test".utf8), params: params)
let session = try VaultSession.open(header: header, password: Data("test".utf8))
let id = UUID()
let sealed = try await session.seal(recordID: id, version: 1, schema: 1, plaintext: Data("hunter2".utf8))
let back = try await session.open(recordID: id, version: 1, schema: 1, sealed: sealed)
precondition(back == Data("hunter2".utf8))
print("M1 seam OK")
```

**Checkpoint:** `swift build && swift test && swift run passfort-cli` → `M1 seam OK`.
`PFCryptoBoundaryTests` extended with the same round trip plus null/closed-session cases from the Swift
side. Commit: `PassFortCrypto: VaultSession actor over the full §6.2 surface`.

---

## Phase 10 — `passfort-cli` proper: `unlock`, `seal`, `open`, `bench`

Add `swift-argument-parser` (Apple, first-party, safe dependency) and give the CLI the subcommands M2
will build on:

```swift
// Package.swift
.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
// passfort-cli target:
dependencies: [
    "PassFortVault", "PassFortCrypto",
    .product(name: "ArgumentParser", package: "swift-argument-parser"),
],
```

**What `Package.resolved` is.** SwiftPM's lockfile — the exact resolved version and commit of every
dependency (direct and transitive). `Package.swift` says "1.5.0 or newer"; `Package.resolved` pins
"1.5.1, commit abc123". Committing it makes `swift build` reproducible on a fresh checkout and in CI.
This is the first real external dependency, so the `deps` CI job (`architecture.md` §13.2) becomes
meaningful — add a step that runs `swift package resolve` then `git diff --exit-code Package.resolved`,
which fails the build if resolution would change the lockfile (a silent dependency drift, or someone
forgot to commit it).

M1 subcommands (M2 adds `add`/`get`/`list`/`edit`/`rm`/`dump`/`export`):

```
passfort-cli bench [--target-ms 500]        # pf_kdf_calibrate; print params + measured time
passfort-cli init  <vault.pfvault>          # pf_vault_create; prompt for password (no echo)
passfort-cli unlock <vault.pfvault>         # pf_session_open; report OK / AuthFailed
passfort-cli seal  <vault> --id <uuid> --in <file>    # pf_seal; write sealed blob to stdout/-o
passfort-cli open  <vault> --id <uuid> --in <sealed>  # pf_open; write plaintext
```

- Read passwords with `getpass(3)` — a POSIX function that reads a line from the controlling terminal
  with echo turned off, so the password never appears on screen or in the terminal scrollback. A
  password passed as `--password foo` instead lands in your shell history, in `ps` output, and in any
  process-accounting log — never do that.
- For M1 the "vault" is just the header blob on disk; M2 replaces the file with the SQLite DB and adds
  the `records` table. Keep `init` writing `magic ‖ header` so M2's migration has something to read.
- `*.pfvault` and `*.sqlite` are git-ignored (bootstrap Phase 1) — keep it that way, and make any
  committed test fixture synthetic.

**Checkpoint:** a shell session creates a vault, unlocks it, seals a file, opens it back to identical
bytes — no GUI, no Xcode. Commit: `passfort-cli: bench / init / unlock / seal / open subcommands`.

---

## Phase 11 — CI, and the §12.1 retrospective

### CI

The `native` job already runs `ctest`, so the KAT / tamper / fuzz suites are enforced the moment
they're committed. Add:

- the **sanitizer build** as a second `ctest` invocation in the `native` job (or a matrix leg), so
  ASan/UBSan run on every push, not just locally.
- the **`deps` job**: `swift package resolve && git diff --exit-code Package.resolved`.

### The exit criterion — do this honestly

`architecture.md` §12.1: **if more of your M1 time went into fighting the seam than into the
cryptography, drop C++ and reimplement the crypto in Swift** (vendoring a C Argon2). Write three or
four sentences in a scratch note answering:

- How many hours went to interop friction (POD marshaling, `noexcept` plumbing, Swift not importing
  something) vs. to actual crypto (KATs, AAD design, the manifest MAC)?
- Did any §6.1 rule get violated under pressure, or did they hold?
- Is the WASM port (§6.5, M6) still plausible from this codebase?

If C++ stays: you're done with M1 — proceed to `m2-vault-storage.md`. If it goes: the format in §5 is
language-agnostic, the KATs and tests you wrote all carry over, and M6 re-scopes around SwiftWasm. Either
way M1 answered its question.

---

## Deviations from `architecture.md` §4

- The §4 tree names a `util/` directory for "secure memory, zeroize, canonical encoding". This runbook
  puts that in `internal/` instead (`Secure.hpp`, `Canonical.hpp`, `Bytes.hpp`) — the point is the
  same (shared C++ headers the Swift importer never sees) and `internal/` names the property that
  matters. Rename to `util/` if you prefer to match §4 literally.
- §4 does not give the manifest MAC its own directory; this runbook adds `manifest/` alongside
  `keyring/` and `aead/` rather than folding it into one of them. Update the §4 tree or leave a
  footnote.

## Where this leaves you

- **The whole §6.2 surface is real**, native-tested, and driven from Swift through `VaultSession`.
- **`passfort-cli`** does calibrate → create → unlock → seal → open with no GUI.
- **KATs, tamper, and seam-fuzz** run on every push, under sanitizers.
- **Next:** `m2-vault-storage.md` — GRDB, the `records` schema, `VaultRepository`, the manifest wired
  into every write transaction, the recovery key, and plaintext export.
