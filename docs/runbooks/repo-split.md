# Repository split: PassFortKit, PassFortApp, PassFortCloud

> **Not adopted (2026-10-26): do not follow this runbook.** `PassFortApp` stays one public
> repository holding the app, the engine, the CLI (macOS, and Linux/WSL2 when M6 lands), the sync
> contract and the spec. `PassFortCloud` stays private and keeps its `app/` submodule. Nothing was
> created or moved. Why, from the review:
>
> - **No forcing reason.** The `PassFortCloud` split was needed because the backend is private.
>   Kit and App would both be public. A path-filtered `linux` CI job gives each kind of change its
>   own checks without a second repo.
> - **It would make room for code that doesn't exist yet.** Linux pinning is unresolved (Phase 7
>   below), so M6 may end up small or wait behind M7. Running `filter-repo` costs the same later.
> - **Engine changes aren't rare.** Since 2026-10-15, 30 of 140 commits touched `Packages/`, and
>   M7 (iOS) is mostly engine work: an iOS Botan amalgamation and PFCrypto on iOS. Split, each step
>   becomes a Kit commit, Kit CI, then a pin bump in App and App CI.
>
> **Revisit** only if the Linux code becomes substantial after M6. If that happens, fix these first:
>
> - **Depend on Kit as a remote SwiftPM package pinned by revision, not a submodule.** A plain clone
>   and a ZIP download then build, and a local Kit clone dragged into the workspace replaces the
>   remote copy for engine work. Phase 1 check 2 still has to confirm `unsafeFlags` is accepted.
> - **The extracted tree doesn't build as-is.** Moving the package to the root breaks
>   `native-tests/CMakeLists.txt` (`PFCRYPTO`), `scripts/build_botan.sh` (`VENDOR_DIR`), the paths
>   in `ci.yml`, and the `.gitignore` fixture exception. Without that exception, new fixture vaults
>   are ignored without any warning.
> - **Private-first doesn't protect any secrets.** Kit's history is a subset of `PassFortApp`'s,
>   which is already public. A scan hit means rotating the secret.
> - **Keep a `SECURITY.md` in App** (a pointer to Kit's), since App is where users land.
> - **Keep the contract's history:** add `--path Cloud/openapi.yaml --path Cloud/fixtures/` with a
>   matching rename, or the history from before the move to `SyncAPI/` is lost.
> - **Clear the old package folder before the submodule add.** The untracked `.build/` and
>   `.swiftpm/` stay in `Packages/PassFortKit` after `git rm`, and `git submodule add` refuses a
>   non-empty folder.
> - **Move the local folders first, or skip it.** The move is cosmetic and independent of the rest.
>
> The plan below is kept unchanged as a record.

**Status:** Plan, written 2026-10-26. Not adopted the same day (see the note above).
**Why:** The public `PassFortApp` repo holds the Apple app and everything portable: the C++ core,
storage, sync, the CLI, the sync contract and the specification. The portable CLI (ADR-0010, M6)
would add Linux builds, a second Botan amalgamation and platform code to a repo whose job is the
Mac app. Separate repos keep each repo's contents and CI to one purpose.
**Scope:** repository layout only. No vault-format, seam, API or behaviour change. The deployed
backend, the vault on disk and the installed app are untouched.
**Builds on:** ADR-0010 (no web client; the portable CLI) and the earlier split of `PassFortCloud`
(`architecture.md` rev 15), whose submodule pattern this plan reuses.

---

## The shape

Three GitHub repositories, and a plain local folder that holds clones of them. The folder is not a
repository; GitHub never sees it.

```text
~/dev/projects/PassFort/                 plain local folder, not a git repo
├── PassFortKit/      public, NEW        engine + CLI + sync contract + spec
├── PassFortApp/      public, exists     the macOS app (the iOS app later); slimmed
└── PassFortCloud/    private, exists   the Azure backend
```

Dependencies run one way. `PassFortApp` and `PassFortCloud` each pull `PassFortKit` in as a git
submodule pinned to a commit. `PassFortKit` depends on neither, and no public repo references the
private one's code.

### What each repository is

| | **PassFortKit** (new) | **PassFortApp** (slimmed) | **PassFortCloud** |
|---|---|---|---|
| Purpose | everything portable: builds on macOS, later Linux/WSL2, later iOS | the Apple apps | the sync backend |
| Code | `PFCrypto` (C++ plus vendored Botan, one amalgamation per platform), `PassFortCrypto`, `PassFortVault`, `passfort-cli`, `pf-killtest`, tests, `native-tests/` | `PassFort/`, `PassFortTests/`, `PassFort.xcodeproj`, `UI/`; later `PassFortiOS/` and `PassFortAppCore` | `api/`, `infra/`, `site/` |
| Contract and spec | `SyncAPI/`, `architecture.md`, the ADRs, `SECURITY.md` | the user-facing README | none |
| CI | `swift` (macOS), `native` (macOS), `linux` (new, M6), `deps`, `lint`, `secrets` | app build and tests, palette drift, `lint`, `secrets` | unchanged |
| Pulls in | nothing | Kit at `Packages/PassFortKit` | Kit at `kit/` (replaces `app/`) |

### Where everything goes

| Today | Goes to |
|---|---|
| `Packages/PassFortKit/{Package.swift, Package.resolved, Sources/, Tests/}` | **Kit**, at the repo root |
| `native-tests/`, `SyncAPI/`, `scripts/build_botan.sh`, `.clang-format` | **Kit** |
| `docs/architecture.md`, `docs/adr/`, `SECURITY.md` | **Kit** (the spec lives with what implements it) |
| `docs/development.md` | split: engine and CLI part to **Kit**, app build part stays in **App** |
| runbooks `m1-*`, `m2-*`, `m5-sync`, this plan | **Kit** |
| runbooks `m3-gui`, `m3-vault-management`, `settings-redesign`, `m4-platform`, `m7-ios` | **App** (app-led, even where they touch the library) |
| `PassFort/`, `PassFortTests/`, `PassFort.xcodeproj`, `UI/`, `docs/images/` | **App** |
| `scripts/{install_app.sh, gen_palette.swift, make_icon.swift, make_readme_art.swift}` | **App** |
| `README.md` | stays in **App** (user-facing); Kit gets its own developer-facing README |
| `LICENSE`, `.gitleaks.toml` | both (each repo runs its own secret scan) |
| `.gitignore`, `.github/workflows/ci.yml` | split by what each repo contains |
| `CLAUDE.md` (gitignored, local only) | one per repo, recreated locally |

Mixed runbooks are assigned by who leads the work. Historical runbooks keep their old `passfort-cli`
and path mentions as a record; each gets a one-line pointer instead of a rewrite.

---

## What someone who downloads PassFortApp gets

This is the main regression against today, when one clone is self-contained.

- **`git clone --recurse-submodules`** gives the whole tree, including `Packages/PassFortKit`
  (engine, CLI, native tests). The app builds, and `swift build` of the CLI works from inside the
  submodule. Everything works as it does today.
- **A plain `git clone`** (no flag) leaves `Packages/PassFortKit` empty and the build fails.
  Mitigation: `install_app.sh` runs `git submodule update --init --recursive` when the folder is
  empty, and the README's clone command gains `--recurse-submodules`. Updating later is
  `git pull --recurse-submodules`.
- **"Download ZIP" and source archives do not include submodule contents,** so the app cannot be
  built from them. Mitigation: `install_app.sh` detects a tree with no `.git` and stops with a
  message to clone instead. The README already tells people to clone.
- **The alternative** is `git subtree`, which embeds a copy of Kit inside `PassFortApp` and keeps ZIP
  downloads working. It brings back the duplication this plan removes, so it is not proposed.

---

## Rules that make it work

- **The Xcode project is not edited.** It references `Packages/PassFortKit` as a local package by
  relative path. Mounting the Kit submodule at that exact path keeps the reference valid
  (`~/.claude/rules/xcode.md`: never hand-edit `project.pbxproj`).
- **Pins are by commit, not version.** The library builds with `unsafeFlags`
  (`-enable-library-evolution`). I believe SwiftPM refuses those for versioned remote dependencies
  and allows them for local paths, so submodules fit. Phase 1 checks this.
- **A pin bump is its own commit:** `Bump PassFortKit to <sha>: <why>`.
- **One working copy of Kit to edit.** Edit Kit only in the sibling clone. To try the app against
  unpushed engine commits, fetch them from the sibling into the submodule:
  `git -C PassFortApp/Packages/PassFortKit fetch ../../../PassFortKit`, then check out the commit.
- **No history rewrite of any existing repo.** Kit is created from a filtered fresh clone;
  `PassFortApp` gets ordinary "remove these paths" commits.

### Day-to-day flows

| Change | What happens |
|---|---|
| App-only (UI, settings, install script) | one commit in `PassFortApp` |
| Engine change the app needs | commit in Kit, its CI green, then a pin bump in `PassFortApp` whose CI proves it |
| CLI change | one commit in Kit |
| Linux or WSL fix | one commit in Kit; the app is untouched |
| Sync contract change | Kit first (`SyncAPI/openapi.yaml`), then a pin bump in `PassFortCloud` and its suite and drill, as today |

---

## Phase 0: Decide and document

Confirm the open decisions below. Then write **ADR-0011** (repository layout), amend ADR-0010 and
`architecture.md` §4, §11 and §13.2 so M6's home is Kit, and add the new layout to the runbook index.
No repository is created or changed.

**Checkpoint:** the docs agree with each other and with this plan; the open decisions are answered.

## Phase 1: Pre-flight checks (scratch clones only)

Retire the unknowns before anything real moves. All of this happens in throwaway directories.

1. **Kit at the root.** In a scratch clone, move the package to the root layout. `swift build`,
   `swift test`, and `ctest --test-dir native-tests/build` pass.
2. **Submodule works in Xcode.** In a scratch copy of `PassFortApp`, mount that Kit at
   `Packages/PassFortKit` as a submodule. `xcodebuild build` and `xcodebuild test` pass with
   `CODE_SIGNING_ALLOWED=NO`. This also settles the `unsafeFlags` question.
3. **The extraction tool.** `git filter-repo` runs from a throwaway environment (for example
   `pipx run`), not installed permanently (the minimal-tooling rule).
4. **The ownership table above** is checked against `git ls-files` so no file is unassigned.

**Checkpoint:** all four pass. If check 2 fails, stop and revisit the submodule choice.

## Phase 2: Create PassFortKit

1. Fresh clone, then `git filter-repo` keeping the Kit paths, renaming
   `Packages/PassFortKit/` to the root. Sketch, to be validated in Phase 1:

   ```bash
   git clone --no-local PassFortApp PassFortKit-extract && cd PassFortKit-extract
   git filter-repo \
     --path Packages/PassFortKit/ --path native-tests/ --path SyncAPI/ \
     --path scripts/build_botan.sh --path docs/architecture.md --path docs/adr/ \
     --path docs/development.md --path SECURITY.md --path LICENSE \
     --path .clang-format --path .gitleaks.toml \
     --path docs/runbooks/m1-crypto-core.md --path docs/runbooks/m1-retrospective.md \
     --path docs/runbooks/m2-vault-storage.md --path docs/runbooks/m5-sync.md \
     --path docs/runbooks/repo-split.md \
     --path-rename Packages/PassFortKit/:
   ```

2. Add a Kit `README.md` (developer-facing), `.gitignore`, and the CI workflow with the package
   jobs only.
3. Create the GitHub repo as **private first**, push, and let CI and the full-history secret scan
   run. Only then make it public (asks you first).

**Checkpoint:** Kit CI is green; `swift build --product passfort-cli`, `swift test` and `ctest`
pass from a clean clone; the file list matches the ownership table; the secret scan is clean.

## Phase 3: Slim PassFortApp

1. Remove the moved paths in ordinary commits; add Kit as a submodule at `Packages/PassFortKit`,
   pinned to the Phase 2 commit.
2. CI: `submodules: recursive`; drop the package-only jobs that now run in Kit.
3. `install_app.sh`: initialise the submodule when empty, and stop with a clear message on a
   no-`.git` tree. README: new clone command and update steps.

**Checkpoint:** a clean `git clone --recurse-submodules` builds with `scripts/install_app.sh`;
`xcodebuild test` passes; CI is green; the app launches and opens your vault (by hand).

## Phase 4: Repoint PassFortCloud

Replace the `app/` submodule with `kit/`, update the drill script (`KIT_DIR`), the README, the DTO
generation path (`kit/SyncAPI/`) and its CI.

**Checkpoint:** its test suite and the two-device drill pass against `rg-passfort-dev` (cost $0).

## Phase 5: Documentation sweep

`architecture.md` rev 18 (layout in §4, CI per repository in §13.2), the runbook index in each
repo, `development.md` split, ADR index, a pointer line in the historical runbooks, and a grep for
dangling paths (`../PassFortCloud`, `Packages/PassFortKit`, `docs/`) in all three repos.

**Checkpoint:** the grep list is empty or explained.

## Phase 6: Move the local folders

Create `~/dev/projects/PassFort/` and put the three clones in it. Recreate `CLAUDE.md` in each
repo. The Claude Code memory directory is keyed to the old folder path, so notes saved for this
project need copying to the new key.

**Checkpoint:** everything builds and tests from the new locations.

## Phase 7: Hand off to M6

The Linux spike runs in Kit, on CI first (an Ubuntu x86_64 runner), then in WSL2. Its starting
facts are in ADR-0010 and `architecture.md` §14.21, with one correction found on 2026-10-26: a
`URLSession` server-trust delegate is `unavailable` on Linux, and libcurl's pinned-key option
checks only the leaf certificate, so neither option written there works. The realistic choices are
no pinning at first, or libcurl with an OpenSSL verify callback. The M6 runbook is written in Kit
when the spike starts.

---

## Safety

- Every phase leaves all three repositories working. Phases 1 and 2 change nothing that exists.
- Until Phase 3 lands, `PassFortApp` is exactly as it is now, so Kit can be deleted and redone.
- No force-push, no history rewrite, no branch deletion happens without asking first.
- Pushes and the public flip are separate steps that wait for your go-ahead.

## Risks

| Risk | Handling |
|---|---|
| Plain clones and ZIPs break | the install script and README handle clones; ZIPs are a stated limitation |
| `filter-repo` drops or keeps the wrong files | compare the file list with the ownership table; run the tests from a clean clone |
| Secrets in carried history | private first, full-history scan before it goes public |
| Xcode dislikes a submodule path | Phase 1 check 2, before anything real moves |
| Pin-bump friction on engine changes | engine changes are rare after M5; UI work is app-only |
| Docs and paths rot | Phase 5 grep across all three repos |

## Rough effort

My estimate, not from any earlier runbook: Phases 0–6 are mostly mechanical, about five to seven
working sessions, with Phase 1 and Phase 3 the ones most likely to surprise.

## Open decisions (confirm before Phase 0)

1. Three repos with the CLI inside Kit, or four with the CLI on its own? Proposed: three.
2. Kit's `Package.swift` at the repo root, mounted at `Packages/PassFortKit`? Proposed: yes.
3. The name `PassFortKit`? Proposed: yes, it matches the existing package.
4. The parent folder as a plain directory, not a superproject repo? Proposed: plain.
5. Accept that "Download ZIP" cannot build the app, with the install script's message as the
   mitigation? Proposed: yes.
6. Spec and ADRs live in Kit (not the app repo)? Proposed: yes.
