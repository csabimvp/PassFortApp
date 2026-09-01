# ADR-0007: Recovery-key DEK slot folded into vault-header format v1

**Status:** Accepted
**Date:** 2026-09-01

## Context

§5.6 requires a **recovery key** shipping in M2: 256 random bits, shown once at vault
creation, that can open the vault if the master password is lost. Mechanically this is a
second `wrapped_dek` slot in the vault header (§5.3) — a second wrapped copy of the same
DEK, its KEK derived from the recovery key instead of the password.

M1 shipped the header codec (`keyring/header.cpp`) with a **single fixed slot**: a 132-byte
layout, `format_version = 1`, no `slot_count` field and no room for a second slot. The M1
runbook (`m1-crypto-core.md`, Phase 5) flagged the choice and recommended building
`slot_count` in then; that recommendation was not taken.

Adding the second slot now is a header **format** change, which per `CLAUDE.md` and §5.3
normally means a new `format_version`, an ADR, and a re-seal migration that rewrites every
existing vault header.

The mitigating fact: **nothing has shipped**. No vault with real data exists on any host.
The only checked-in fixture (`Tests/PassFortVaultTests/Fixtures/v1/vault.sqlite`) is an
empty database with no header and no sealed records. The `format_version = 1` on disk today
exists only in throwaway developer vaults that are recreated at will.

## Decision

**Redefine `format_version = 1` to carry a `slot_count` byte and an optional second slot.
No version bump, no re-seal migration.**

Revised §5.3 header layout:

```
magic          "PFV\x01"   4B
format_version u16          = 1
vault_uuid     16B
kdf_id         u8           (1 = argon2id)
kdf_m_kib      u32
kdf_t          u32
kdf_p          u32
kdf_salt       16B
wrap_alg       u8           (1 = XChaCha20-Poly1305)
slot_count     u8           (1 = password only, 2 = password + recovery)
slot[0]        wrap_nonce 24B ‖ wrapped_dek 32B ‖ tag 16B     — KEK from Argon2id(password)
slot[1]        wrap_nonce 24B ‖ wrapped_dek 32B ‖ tag 16B     — KEK from HKDF(recovery_key),
                                                                present iff slot_count == 2
created_at     i64
```

- **AAD for every slot's AEAD is every header byte through `slot_count`.** `slot_count` is
  therefore authenticated — an attacker cannot strip `slot[1]` and rewrite `slot_count` to
  `1` without failing the tag check on `slot[0]`.
- **Both slots wrap the identical 32-byte DEK.** A recovered session is byte-for-byte the
  same as a password session because it unwraps the same DEK.
- **The recovery key is not password-derived.** It is 256 bits of CSPRNG output — already a
  full-strength key — so it is fed straight into `HKDF-SHA-256` (`info = "pf-rk-v1"`) to get
  its KEK. No Argon2id pass; Argon2id exists only to stretch a low-entropy password.
- **Display form is Crockford Base32**, grouped `XXXX-XXXX-…`. Crockford over RFC 4648 for
  the human-transcription properties: no `I/L/O/U`, case-insensitive, and an optional check
  symbol that catches transcription errors. 256 bits is 52 Base32 characters plus the check
  symbol.
- Seam functions (§6.2): `pf_recovery_wrap(Session*, const uint8_t rk[32]) -> BytesResult`
  (returns a new header with `slot_count = 2`) and
  `pf_recovery_open(const uint8_t* header, size_t, const uint8_t rk[32]) -> SessionResult`
  (parallel to `pf_session_open`).

This is a one-time exception justified solely by "the format has not shipped." The
versioned-format discipline (`CLAUDE.md`: a format change needs an ADR + re-seal migration)
applies in full from the first release onward. The migration machinery gets its first real
exercise when a **schema** change lands — the fixture harness in `m2-vault-storage.md`
Phase 3 is already in place for that.

## Consequences

- **M1's header codec is now non-conformant with the revised v1 spec** and is rewritten in
  M2 Phase 8: insert `slot_count`, extend `header_decode` to try each present slot, add
  `header_encode`-with-recovery. Any developer vault at the old 132-byte layout is discarded
  and recreated — there is no upgrade path and none is needed.
- **No `format_version = 2` and no header re-seal migration in M2.** One fewer ADR-worthy
  format, one fewer migration to write and test.
- `slot_count` is fixed at 1 or 2 forever in v1. A third slot (e.g. an enterprise escrow
  key) would be a real `format_version = 2` with a real migration — correct, because by then
  the format has shipped.
- Header sizes: 52-byte fixed prefix becomes 53 (`slot_count` added); a 1-slot header is
  133 bytes (was 132), a 2-slot header 205. The layout is `slot_count`-prefixed, not
  fixed-size — `header_decode` computes the `created_at` offset from `slot_count`.
- Losing the master password is now survivable in M2 without waiting for a later milestone.

## Alternatives considered

- **Bump to `format_version = 2` with a re-seal migration (by the book).** Rejected for M2:
  it writes and tests a migration for a format that never had a user, to prove machinery
  that a schema change will exercise for real anyway. Pure ceremony given nothing shipped.
- **Defer the recovery key to M3/M4, do the v2 bump then.** Rejected: M2's own scope in §12
  lists the recovery key, and shipping M2 with no recovery path means every developer and
  early vault is one forgotten password away from total loss for an extra milestone. The
  cost of doing it now (redefine an unshipped format) is near zero.
- **Keep `slot_count` out; store the recovery slot in a `vault_meta` row instead of the
  header.** Rejected: the header is the one authenticated, self-describing unlock structure,
  and C++ owns its whole codec (§5.3). Splitting unlock material between the header and a
  Swift-managed table reintroduces exactly the "Swift assembles authenticated bytes" footgun
  §5.3 exists to avoid.
