# PassFort build runbooks

Step-by-step runbooks, one per milestone (`architecture.md` §12). Each is written the same way as
`../bootstrap.md`: numbered phases, the exact commands, an explanation of *why* each step is shaped the
way it is, and a **Checkpoint** you can verify before moving on. Follow them top to bottom.

A runbook is written **when the previous milestone is done**, not before — a runbook drafted two
milestones ahead is fiction, because it can't account for what the earlier work taught you. If the
runbook you need doesn't exist yet, that's the signal to ask for it.

| Milestone | Runbook | Status |
|---|---|---|
| **M0** Toolchain spike + M1 scaffolding | [`../bootstrap.md`](../bootstrap.md) | ✅ done |
| **M1** Crypto core + seam | [`m1-crypto-core.md`](m1-crypto-core.md) | ▶ current |
| **M2** Vault + storage | [`m2-vault-storage.md`](m2-vault-storage.md) | drafted, starts after M1 |
| **M3** GUI | — | write after M2 (folds in `bootstrap.md` Phase 6) |
| **M4** Platform integration | — | write after M3 |
| **M5** Sync (Azure) | — | write after M4 (do the Azure spike first, `architecture.md` §15 step 6) |
| **M6** Web client | — | write after M5 (or pull forward — §12 note 3) |
| **M7** Hardening | — | write after M6 |

## How these relate to the other docs

- **`architecture.md`** is the specification. The runbooks implement it and cite its `§` numbers; where
  a runbook and the architecture disagree, the architecture wins and the runbook has a bug.
- **`adr/`** holds the reasoning behind load-bearing choices. A runbook step that follows from an ADR
  says so by number instead of re-arguing it.
- **`bootstrap.md`** is the M0 runbook. It also stood up the M1 *scaffolding* (Botan, CMake harness,
  CI). `m1-crypto-core.md` picks up exactly where its "Where this leaves you" section stops.

## The C++ exit criterion (`architecture.md` §12.1)

M1 is also the go/no-go on C++ itself. **If, at the end of M1, more of your time went into the seam
than into the cryptography, drop C++ and reimplement the crypto in Swift** (vendoring a C Argon2). The
vault format in §5 is language-agnostic by construction, so that port is mechanical. `m1-crypto-core.md`
ends with a short retrospective to force that call while it's cheap to make.
