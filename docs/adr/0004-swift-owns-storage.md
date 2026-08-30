# ADR-0004: Swift owns storage; C++ owns only keys

**Status:** Accepted
**Date:** 2026-08-24
**Amends:** ADR-0002 (narrows the seam), ADR-0003 (moves the index out of C++)

## Context

The rev-1 architecture put the whole vault in C++: key derivation, record encryption, the SQLite gateway, the repository, and an in-memory decrypted index. Swift was a view layer that asked for one field at a time. The property that bought was appealing — *plaintext never crosses the seam* — and it implied a boundary carrying record CRUD, queries, and model types.

Then the M0 spike happened. Swift 6.3.3's C++ interop moves bytes across a function call perfectly well, but the conveniences you would want for a *wide* boundary do not work (ADR-0002 lists the exact failures: no `Array(cxxVector)`, no `std.string(swiftString)`, no pointer-returning member functions). Every collection and every string at the seam becomes hand-written marshaling.

That reframes the cost. A dozen byte-oriented functions is a bounded, one-time job. A repository facade — list, search, filter, paginate, model types in both directions — is hand-written marshaling forever, and it is the part of the app most likely to change while the GUI is being built.

Two further observations undercut the rev-1 property:

- **It was always partial.** A password has to reach a SwiftUI `TextField` to be displayed. Plaintext was going to be in unwipeable Swift memory either way; the rev-1 design reduced how *much* and for how long, not whether.
- **The security-critical parts are properties of the format, not of the language.** Argon2id parameters bound into the header AAD, record identity and version bound into the record AAD, the manifest MAC over the record set — all of these work identically no matter who calls `sqlite3_step`.

What genuinely must stay in C++ is the thing Swift cannot do safely: hold key material in memory that gets zeroized, with a locking allocator, and never hand it out.

## Decision

The seam moves down. C++ (`PFCrypto`) owns **keys and only keys**:

- Argon2id, the HKDF hierarchy, DEK wrap/unwrap, session lifetime and zeroization;
- record seal/open, including **assembling the AAD** from typed parameters, so its canonical layout is defined in one place;
- vault header encoding and decoding, so Swift never constructs canonical bytes that something else authenticates;
- the manifest MAC, exposed as a streaming `init`/`update`/`finish` because `k_manifest` cannot leave.

Swift owns everything else: SQLite (GRDB), schema and migrations, the record model and its payload encoding, search, tombstones, sync, Keychain, biometrics, and the UI.

The resulting surface is roughly twelve functions taking integers and `(pointer, size)` pairs — architecture §6.2. No collection, string, or model type crosses.

Module layout follows: `PFCrypto` (C++) → `PassFortCrypto` (the only Swift module compiled with `.interoperabilityMode(.Cxx)`) → `PassFortVault` (plain Swift, cannot import the C++ module at all).

## Consequences

- **The interop risk retires in M1.** `passfort-cli` is a Swift executable driving the full seam, so the seam is built and exercised in week one rather than discovered in week eight.
- The seam is small enough to fuzz exhaustively and to hand-audit in an afternoon.
- Storage gets built in the language with the better tooling for it. Migrations, queries and tests stop being interop problems.
- **Cost, stated plainly:** decrypted payloads now live in Swift `Data`, which cannot be reliably zeroized (CoW, ARC). The unlocked in-memory search index — titles, usernames, URLs — is Swift-side and unwipeable until lock. Architecture §3.4 records this as an accepted limitation rather than pretending it away.
- Keys are still never in Swift. A memory dump of the unlocked process yields plaintext records but not the DEK, so it does not yield the *file*. That distinction is the whole remaining value of the C++ layer, and it is worth keeping.
- Mitigations become behavioural rather than structural: decrypt on demand, scope decrypted values to a single view, drop the index on lock, auto-lock aggressively.
- **The exit ramp is now cheap.** With the seam this narrow and the format language-agnostic, reimplementing `PFCrypto` in Swift (vendoring a C Argon2) is a mechanical port. Architecture §12.1 makes that an explicit checkpoint at the end of M1.

## Alternatives considered

- **Keep the rev-1 wide boundary (C++ owns the vault).** Best security story on paper, and the property it protects turns out to be partial anyway. Rejected: the marshaling cost lands squarely on the layer that changes most during GUI work, and it defers the interop risk to M3.
- **Pure C++ with a Qt or ImGui front end.** Removes interop entirely, and fails the actual goal — a native macOS GUI — while pushing Keychain, Touch ID and CloudKit into Objective-C++, which is interop again in a less pleasant form.
- **Pure Swift, no C++ at all.** Viable, but doesn't escape native interop either: there is no Argon2id in CryptoKit or swift-crypto, so you vendor the C reference implementation or drop to PBKDF2. Memory-hardness is the property doing the real work against offline cracking, so PBKDF2 is a downgrade not worth taking. It also deletes a stated learning goal. Kept as the documented fallback in §12.1.
- **C++ owns crypto *and* the payload encoding.** Tempting for symmetry, but it drags a serialization format across the seam and buys nothing — the payload is already inside the AEAD.
