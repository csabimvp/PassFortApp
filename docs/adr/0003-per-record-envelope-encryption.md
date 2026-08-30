# ADR-0003: Per-record envelope encryption in SQLite

**Status:** Accepted — amended by [ADR-0004](0004-swift-owns-storage.md)
**Date:** 2026-08-24

> **Amendment (ADR-0004):** the encryption design below stands entirely — envelope encryption, per-record AEAD, AAD binding, the manifest MAC. What changed is *who executes it*: Swift (GRDB) drives SQLite and holds the unlocked in-memory index; C++ seals and opens the record blobs and computes the manifest MAC by streaming. Read "the core decrypts into an in-memory index in `secure_vector`" below as "the Swift repository decrypts into an in-memory index" — and see architecture §3.4 for what that costs.

## Context

Three ways to keep the vault encrypted at rest:

1. **One encrypted file.** Decrypt the whole blob into memory on unlock, re-encrypt and rewrite on every save. Trivially correct, trivially atomic.
2. **SQLCipher / an encrypted-page SQLite build.** Transparent whole-database encryption; SQL works normally.
3. **Plain SQLite, per-record AEAD ciphertext in a BLOB column**, with only non-sensitive metadata in the clear.

Sync (M5) is the decider. Option 1 means every edit rewrites and re-uploads the entire vault, and two devices editing different records is an unresolvable whole-file conflict. Option 2 encrypts pages, not records — the sync unit is still the file, and it adds a third-party SQLite fork to vendor and keep current.

Option 3 makes the record the unit of encryption, storage, *and* sync, which is also the unit the user thinks in.

## Decision

Plain `libsqlite3` with per-record envelope encryption.

- A random 32-byte **DEK** encrypts records. The **KEK**, derived from the master password with Argon2id, only ever wraps the DEK — so changing the master password re-wraps 32 bytes instead of re-encrypting the vault.
- Record subkeys come from `HKDF(DEK, info=...)`: `k_record`, `k_index`, `k_manifest`.
- Each record: `XChaCha20-Poly1305(k_record, random 24B nonce, CBOR payload, aad = vault_uuid ‖ record_uuid ‖ record_version ‖ schema_version)`.
- **Everything sensitive is inside the ciphertext**, including title, username and URL. Plaintext columns are limited to `uuid`, `version`, `updated_at`, `is_deleted`, and optional blind indexes.
- A vault-level `manifest_mac = HMAC-SHA-256(k_manifest, vault_version ‖ Σ_sorted(uuid ‖ version ‖ SHA-256(ct)))` is verified on unlock.

The AAD binding and the manifest exist for reasons worth restating, because they're the two things this design gets right that naive versions don't:

- AEAD proves a blob is *intact*. It does not prove it is *the right blob*. Binding `record_uuid` stops an attacker with file access from swapping your bank record's ciphertext onto a throwaway record; binding `record_version` stops them restoring last month's password.
- Per-record AEAD says nothing about the *set* of records. Deleting a row, or restoring an older copy of the whole file, leaves every surviving record verifying perfectly. The manifest MAC — plus a monotonic `vault_version` cached in the Keychain — is what detects that.

## Consequences

- Edits touch one row. Sync moves one blob. Conflicts resolve per record.
- Search and sort require plaintext, so the core decrypts into an in-memory index in `secure_vector` at unlock. Fine at hobby scale (thousands of records); it would need rethinking at hundreds of thousands.
- Every write is one transaction covering the row **and** the manifest. They must never diverge — this is the main correctness risk the design introduces, and it needs a test that kills the process mid-write.
- Encrypting titles and URLs costs the ability to query them in SQL. Deliberate: metadata leak is a real leak, and "which sites do you have accounts on" is exactly what an attacker with disk access wants.
- Ciphertext length still leaks approximate note length. Padding to 256-byte buckets is cheap and open (architecture §14.7).
- The format is ours, so migrations and a tested export path are mandatory, not optional (architecture §5.6).

## Alternatives considered

- **Single encrypted file** — simplest and genuinely correct; loses on sync granularity and on rewriting the whole vault per keystroke-saved. Reconsider only if sync is abandoned.
- **SQLCipher** — solid, battle-tested, and would let us skip most of §5. Rejected because the sync unit stays the file, it vendors a SQLite fork, and it hides exactly the mechanics this project exists to learn.
- **Encrypting field-by-field within a record** — finer granularity than anything needs, multiplies nonce management, more AEAD tags than data on short fields.
