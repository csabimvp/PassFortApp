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
| **M3 addendum** Vault backup & restore | [`m3-vault-management.md`](m3-vault-management.md) | ✅ Phases 0–5 and 7 built, by-hand checks done (2026-10-26); Azure (6) unblocked by M5 but not built |
| **M4** Platform integration | [`m4-platform.md`](m4-platform.md) | ⏸ scaled back 2026-10-21 — no Keychain, Touch ID or notarization for a personal-use app; Phases 1–2 and 4 were tried and reverted; Phases 6 (lock on sleep/screen lock) and 7 (concealed pasteboard) built — see the note at the top of the runbook |
| **M5** Sync (Azure) | [`m5-sync.md`](m5-sync.md) | ✅ done (2026-10-25) — Phases 0–14; deployed as `rg-passfort-dev` (`eastus2`), where the drill and the two-device checkpoint pass with pinning; doc sweep is `architecture.md` rev 16. The backend lives in the private `PassFortCloud` repository (rev 15). Left to read off the portal: the cost page, the per-request timeout, regional Table prices |
| **M3 addendum** Settings redesign | [`settings-redesign.md`](settings-redesign.md) | ✅ done — built 2026-10-25 (Phases 0–8) from the review in `UI/settings-review.md`; by-hand checks done and merged to `main` 2026-10-26 |
| **Repo split** PassFortKit / PassFortApp / PassFortCloud | [`repo-split.md`](repo-split.md) | ✗ not adopted (2026-10-26) — one repository stays home to the app, the engine and the CLI (macOS, and Linux/WSL2 from M6); the plan is kept as a record, with what to fix if Linux code ever justifies revisiting — see the note at the top of the runbook |
| **M6** Portable CLI (Linux first) | [`m6-portable-cli.md`](m6-portable-cli.md) | ✅ done 2026-10-30 (`architecture.md` rev 24), apart from one deferred by-hand check: Phase 7's Windows clipboard in WSL2. The CLI builds, passes and syncs with pins on Linux and in WSL2 (libcurl + OpenSSL, [ADR-0011](../adr/0011-linux-tls-pinning-libcurl-openssl.md)); one Botan amalgamation per target (ADR-0001 amendment); keys `mlock`ed on both platforms; a `linux` CI job. The spike branch `m6-spike` is kept until deleted on request ([ADR-0010](../adr/0010-no-web-client-portable-cli.md)) |
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
