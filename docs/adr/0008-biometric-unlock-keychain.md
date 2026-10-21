# ADR-0008: Biometric unlock keeps the master password in a Touch ID-gated Keychain item

> **Amended 2026-10-21: not adopted.** Touch ID unlock and every other Keychain use were dropped
> before anything shipped: the data-protection keychain needs a `keychain-access-groups` entitlement,
> which makes signing depend on a provisioning profile tied to an Apple ID, for a hobby app that only
> needs master-password unlock. The design below is kept as the answer if Touch ID is ever wanted.

**Status:** Accepted
**Date:** 2026-10-21

## Context

§12 M4 requires Touch ID unlock. Mechanically that needs a persisted secret that Touch ID can
release and that reconstructs a vault session. There are two shapes:

- **A — password in the biometric Keychain.** Store the master-password bytes in a generic-password
  item gated by `SecAccessControl`. Touch ID returns the password and the existing
  `Vault.unlock(password:)` runs unchanged.
- **B — a biometric header slot.** Store a random 256-bit `bio_unlock_key` in the Keychain and add a
  third header slot (`slot_count = 3`) that wraps the DEK under `HKDF(bio_unlock_key)`. This needs
  new `pf_biometric_wrap` / `pf_biometric_open` seam entries, a C++ header-codec change, and
  `format_version = 2` with the project's first real re-seal migration (ADR-0007 says a format
  change needs exactly that).

Nothing else in M4 or M5 forces a `format_version = 2` bump.

## Decision

**Option A.** Biometric unlock stores the **master-password bytes** in a biometric-gated,
passcode-required, non-syncable generic-password Keychain item:

- `kSecAttrService = "app.passfort.biometric-unlock"`, `kSecAttrAccount = <vault_uuid>`.
- `SecAccessControl` flags `[.biometryCurrentSet]`, accessible `WhenPasscodeSetThisDeviceOnly`
  (never synced, never backed up to another device).
- Touch ID gates retrieval; the `Vault.unlock(password:)` path is unchanged.
- Enabling requires a *successful password unlock* first: you can only cache a password you have
  just proved.
- `rewrap` (master-password change) updates the item. Disabling Touch ID, a failed manifest check,
  or `.biometryCurrentSet` invalidation (a fingerprint was added or removed) deletes it.

## Consequences

- No format change, no seam change, no migration. The platform code is confined to
  `PassFort/Platform/` (`Security` + `LocalAuthentication`).
- **New §3.4 limitation:** with Touch ID enabled, the master password is persisted on the device,
  ACL-gated, never synced. If the Keychain ACL is ever bypassed (an out-of-scope adversary, §3.3),
  the master password leaks, not a device-local wrapping key as under option B.
- A future `format_version = 2` that has its own reason to exist may revisit option B. This ADR is
  not a barrier to that.

## Alternatives considered

- **Option B (biometric header slot).** Cleaner key story: only a device-local wrapping key leaks,
  and toggling Touch ID off and on rotates it. Rejected for M4: it spends a platform-integration
  milestone on a vault-format break and the first re-seal migration, which is milestone-sized work
  that belongs with a v2 bump that has another reason to exist.
- **`.userPresence` instead of `.biometryCurrentSet`.** Rejected as the default: the passcode
  fallback weakens a password-manager unlock. Can be offered as an opt-in later if the UX bites.
- **Storing a derived key instead of the password.** Rejected: `Vault.unlock` takes a password, so
  caching a key would need a new seam entry for no security gain over an ACL-gated password.
