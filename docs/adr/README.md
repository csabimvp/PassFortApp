# Architecture Decision Records

One file per decision, numbered, immutable once accepted — corrections go in a short amendment block at the top pointing at the newer ADR, never in the body. If a decision changes, write a new ADR that supersedes the old one — don't edit history. Commits that follow from an ADR reference it by number instead of re-arguing the reasoning in the commit body.

| # | Title | Status |
|---|---|---|
| [0001](0001-botan-static-amalgamation.md) | Botan 3, statically linked as a minimized amalgamation | Accepted (amended 2026-08-30: pin 3.12.0 → 3.13.0; 2026-10-26: `locking_allocator` added) |
| [0002](0002-cxx-swift-boundary-style.md) | Opaque handles and `noexcept` free functions at the Swift↔C++ seam | Accepted (amended by 0004) |
| [0003](0003-per-record-envelope-encryption.md) | Per-record envelope encryption in SQLite | Accepted (amended by 0004) |
| [0004](0004-swift-owns-storage.md) | Swift owns storage; C++ owns only keys | Accepted |
| [0005](0005-azure-sync-backend.md) | Custom Azure sync backend, not CloudKit | Accepted (auth amended by 0009; web client dropped by 0010) |
| [0006](0006-web-client-wasm-core.md) | The web client runs the crypto core as WebAssembly | Superseded by 0010 |
| [0007](0007-recovery-key-header-slot.md) | Recovery-key DEK slot folded into vault-header format v1 (no migration) | Accepted |
| [0008](0008-biometric-unlock-keychain.md) | Biometric unlock keeps the master password in a Touch ID-gated Keychain item | Accepted, then not adopted (amended 2026-10-21) |
| [0009](0009-sync-auth-key.md) | Sync authenticates with a DEK-derived key, stored server-side only as a hash | Accepted |
| [0010](0010-no-web-client-portable-cli.md) | No web client; a portable CLI reaches the vault where the apps can't be installed | Accepted |

## Template

```markdown
# ADR-NNNN: Title

**Status:** Proposed | Accepted | Superseded by ADR-XXXX
**Date:** YYYY-MM-DD

## Context
What forces are at play? What did we know at the time?

## Decision
What we're doing, stated plainly.

## Consequences
What this makes easy, what it makes hard, what we now have to live with.

## Alternatives considered
Each with the reason it lost.
```
