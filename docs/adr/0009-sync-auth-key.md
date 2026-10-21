# ADR-0009: Sync authenticates with a DEK-derived key, stored server-side only as a hash

**Status:** Accepted
**Date:** 2026-10-21

## Context

M5 (ADR-0005) puts a custom Azure backend between devices. It must authenticate callers without ever
holding anything that decrypts the vault. `architecture.md` up to rev 11 specified:

- `auth_secret = HKDF-Expand(Argon2id(password, salt), "auth")` — a second output of the same Argon2
  run that produces the KEK (§5.1);
- `POST /session` sends "a challenge-response HMAC over `auth_secret`, never the secret itself", and
  the server compares against `auth_verifier = HMAC(serverPepper, auth_secret)` (§10.4);
- a device token registered at first login so routine sync never touches the password path (§10.4
  step 4);
- the accepted limitation that a breach of Azure exposes the verifier as an **offline-cracking target
  at Argon2 cost**, with OPAQUE/SRP as the deferred fix (§10.4, §14.8).

Working the M5 runbook down to the endpoint level exposed four problems with that design:

1. **It doesn't close.** For the server to verify an HMAC over `auth_secret` against a fresh challenge,
   it needs `auth_secret` itself (or something equivalent). A stored `HMAC(pepper, auth_secret)` can
   only check a value the client sends in the clear. The spec described a challenge-response and a
   one-way verifier at the same time.
2. **The verifier is crackable.** Anything derived only from the password and a salt the server also
   holds (the header is stored server-side for bootstrap) can be brute-forced offline at Argon2 cost
   once the server is breached. Fixing that properly means OPAQUE.
3. **It breaks on a password change.** A new master password means a new Argon2 output, a new
   `auth_secret`, and therefore a flow to re-register the verifier from a device that is still
   authenticated under the old one. The recovery path is worse: a device that recovered with the
   recovery key has no password-derived `auth_secret` for the *old* password, so it cannot
   authenticate to update the verifier at all.
4. **A joining device must authenticate after reading a header the server supplied.** With a
   password-derived secret, a hostile server could serve a forged header with trivially cheap KDF
   parameters and harvest a response that is cheap to crack, unless every client is careful to finish
   the DEK unwrap first.

All four come from deriving the credential from the **password**. The vault already has a
high-entropy secret that every legitimate device holds after unlock and that never changes when the
password does: the **DEK**.

## Decision

1. **Derive the sync credential from the DEK:** `k_auth = HKDF-Expand(DEK, "sync-auth", 32)`, alongside
   `k_record`, `k_index` and `k_manifest` in the session handle. The Argon2-side `auth_secret` is
   removed from the hierarchy; Argon2id now has exactly one output (the KEK).
2. **One new seam function:** `pf_session_auth_key(PFSession*, uint8_t* out, size_t out_len)` copies the
   32 bytes out (out-buffer convention of `pf_session_vault_uuid`; `noexcept`; `BadInput` on a null or
   wrong-length buffer). `VaultSession.authKey()` wraps it. `k_auth` is the **one** DEK-derived value
   that leaves C++, because showing it to the server is its purpose; it is domain-separated by HKDF and
   reveals nothing about the DEK or the other subkeys.
3. **The server stores only `SHA-256(k_auth)`** (set at vault creation) and compares with a
   constant-time equality. No pepper: the input is a 256-bit random-derived value, so the hash is not
   brute-forceable and a pepper adds a secret to manage for no gain.
4. **Sessions:** the client sends `k_auth` in the body of `POST /vaults/{id}/session` over TLS (SPKI
   pinned in the native clients) and receives a 15-minute HS256 JWT bound to the vault and device. The
   token lives in memory only. On `401` the client opens a new session. There are **no refresh or
   device tokens**: sync runs only while the vault is unlocked, and an unlocked device can always
   re-derive `k_auth`.
5. **Vault creation is gated by an enrollment secret** (an app setting typed once when enabling sync),
   so the public endpoint cannot be used to fill the storage account. Failed session attempts back off
   exponentially per vault.
6. `GET /vaults/{id}/header` stays unauthenticated, because a joining device needs the KDF salt before
   it has the DEK. The 122-bit random vault UUID is the capability; the header is the same offline
   target an A2 adversary already holds (§3.1).

## Consequences

- **A full Azure breach yields nothing to crack.** Table Storage holds sealed blobs, plaintext
  envelopes and `SHA-256` of a high-entropy key; app settings hold a JWT key and the enrollment secret.
  None of it narrows the search for the master password. The §10.4 offline-cracking limitation is gone,
  and OPAQUE/SRP is no longer needed for it (§14.8 closes).
- **Password changes and recovery need no server-side credential update.** Re-wrapping the DEK (master
  password change, recovery-key rotation, recovery) leaves `k_auth` unchanged, so every device keeps
  syncing. Only the header changes, and it propagates as a header update (`m5-sync.md` A.8).
- **A forged header can't harvest anything.** Without the right KEK the DEK unwrap fails, so no
  `k_auth` exists to send. The "unwrap before answering" ordering is enforced by construction rather
  than by client discipline (`m7-ios.md` Phase 5).
- **`k_auth` is a bearer credential.** Anyone who obtains it (a TLS break against a client that can't
  pin, such as the M6 web client; a memory dump of an unlocked device) can read and write sealed blobs
  until the DEK changes. They still cannot decrypt anything, and forged writes fail `pf_open` on every
  device; the damage is denial of service against the server copy. The short JWT TTL limits a leaked
  *token*; a leaked *key* is only rotated by a DEK rotation.
- **DEK rotation now also rotates the sync credential.** It is deferred past M5 anyway (it needs a
  key-generation id in the format, its own ADR); when it lands it must re-register `SHA-256(k_auth')`
  under the old session.
- **Key hierarchy change, not a format change.** Nothing stored in a vault file depends on
  `auth_secret`, and nothing was ever sent to a server; no vault needs migrating. The native KAT suite
  gains a `k_auth` vector, and the seam fuzz suite gains the new function (and, in M6, its WASM export).
- **The anti-replay value of a challenge-response is given up.** A recorded session request can be
  replayed — but only by someone who could already read the TLS stream, which is the same position as
  holding the JWT it returns.

## Alternatives considered

- **Keep the password-derived `auth_secret` and send it in the clear under TLS, storing
  `HMAC(pepper, auth_secret)`.** Closes problem 1, but keeps problems 2–4: the verifier stays
  crackable at Argon2 cost given the pepper, and password changes and recovery still need a
  credential-rotation flow.
- **Password-derived challenge-response with the server holding `auth_secret` encrypted under a
  pepper** (the first M5 sketch's fallback). The server would hold a value from which a password-derived
  secret is recoverable on a full breach — strictly worse at rest than this decision, and still
  problems 3–4.
- **OPAQUE / SRP.** The correct answer for a *password*-based login, and no longer needed: there's no
  reason to authenticate with the password when every legitimate client holds a 256-bit key. It would
  also be the most complex piece of cryptography in the project, with no Botan module for it.
- **Static Web Apps' built-in identity (GitHub / Microsoft login) as the credential.** Ties vault access
  to a third-party account and an OAuth flow in every native client; it can still be added later in
  front of the API as a coarse DoS gate, orthogonal to this decision.
- **Long-lived device tokens alongside the key** (§10.4 step 4). Adds a bearer secret that must be
  stored on disk — the project has no Keychain since §14.18 — for no benefit while sync only runs
  unlocked.
