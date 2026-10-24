# PassFort build plans

One implementation plan (a runbook) per milestone (`architecture.md` §12), the plans the system was
built against. The specification and the ADRs say *what* to build and *why*. A runbook says in what
order, and how to tell that each step is right. It breaks the milestone into numbered phases, and
each phase has the exact change, the reasoning behind its shape, and a **Checkpoint**: the tests or
checks that must pass before the next phase starts.

The code was written by an AI coding agent working through these plans one phase at a time (see the
[README](../../README.md#architecture)). A checkpoint is the
acceptance gate for that work. When a phase showed the plan was wrong, the plan was corrected in place,
and the spec or an ADR as well if the mistake reached that far.

A runbook is written **when the previous milestone is done**, not before — a runbook drafted two
milestones ahead is fiction, because it can't account for what the earlier work taught you. If the
runbook you need doesn't exist yet, that's the signal to ask for it.

| Milestone | Runbook | Status |
|---|---|---|
| **M0** Toolchain spike + M1 scaffolding | `bootstrap.md` (retired 2026-10-23; see below) | ✅ done |
| **M1** Crypto core + seam | [`m1-crypto-core.md`](m1-crypto-core.md) | ✅ done ([retrospective](m1-retrospective.md)) |
| **M2** Vault + storage | [`m2-vault-storage.md`](m2-vault-storage.md) | ✅ done |
| **M3** GUI | [`m3-gui.md`](m3-gui.md) | ✅ done — Phases 1–9 done; Phase 10 ("last used") deliberately deferred |
| **M3 addendum** Vault backup & restore | [`m3-vault-management.md`](m3-vault-management.md) | ✎ Phases 0–5 and 7 built (3, 4, 7 await by-hand checks); Azure (6) blocked on M5 |
| **M4** Platform integration | [`m4-platform.md`](m4-platform.md) | ⏸ scaled back 2026-10-21 — no Keychain, Touch ID or notarization for a personal-use app; Phases 1–2 and 4 were tried and reverted; Phases 6 (lock on sleep/screen lock) and 7 (concealed pasteboard) built — see the note at the top of the runbook |
| **M5** Sync (Azure) | [`m5-sync.md`](m5-sync.md) | ✎ detailed design (reworked 2026-10-21) — Part A is the low-level design (Azure resources, data model, API, auth, sync algorithm, app views); the Azure spike (Phase 0.1) gates the rest — its local half passed 2026-10-21, the deploy half is pending (run it from Cloud Shell); its design changes D1–D8 are ratified by ADR-0009 and `architecture.md` rev 12. Phases 1–2 built (2026-10-22), Phases 3–4 built (2026-10-23; the Azurite CI run is pending); local toolchain trimmed to Node only (rev 13); the backend moved to the private `PassFortCloud` repository (rev 15). Phases 5–11 built; **Phase 12 deployed 2026-10-24** (`eastus2`; the drill passes against Azure with pinning, after a teardown and redeploy) -- Phase 13 (the app) next |
| **M6** Web client | — | write after M5 (or pull forward — §12 note 3) |
| **M7** iOS client | [`m7-ios.md`](m7-ios.md) | ✎ sketch — written ahead of cadence (2026-10-21); depends on M5 only, not M6; only Phase 0 (the spikes) is actionable, the rest is a plan to validate |
| **M8** Hardening | — | write after M7 |

## How these relate to the other docs

- **`architecture.md`** is the specification. The runbooks implement it and cite its `§` numbers; where
  a runbook and the architecture disagree, the architecture wins and the runbook has a bug.
- **`adr/`** holds the reasoning behind load-bearing choices. A runbook step that follows from an ADR
  says so by number instead of re-arguing it.
- **[`../development.md`](../development.md)** is the standing build-and-test guide. Once a
  milestone's commands are stable they move there, and the runbook remains a record of how the
  milestone was built.
- **Retired 2026-10-23:** `bootstrap.md` (the M0 runbook, which also stood up M1's Botan, CMake and
  CI scaffolding) and `cli-guide.md` (a hands-on `passfort-cli` walkthrough). Their commands now
  live in `development.md`. The older runbooks still mention them by name; the originals are in git
  history.

## The C++ exit criterion (`architecture.md` §12.1)

M1 is also the go/no-go on C++ itself. **If, at the end of M1, more of your time went into the seam
than into the cryptography, drop C++ and reimplement the crypto in Swift** (vendoring a C Argon2). The
vault format in §5 is language-agnostic by construction, so that port is mechanical. `m1-crypto-core.md`
ends with a short retrospective to force that call while it's cheap to make.
