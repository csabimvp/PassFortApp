# Settings redesign

**Status:** Phases 0–8 built (2026-10-25) on the `settings-redesign` branch, one commit per phase;
the by-hand checks below are the maintainer's, then merge.
**Source:** the review in `UI/settings-review.md` and its mockups (`UI/mockups/Settings.dc.html`,
`SettingsStates.dc.html`; local only). The review's problem numbers (1–6) are cited below.
**Scope:** app target only (`PassFort/`, `PassFortTests/`). No vault-format change, no schema change,
no seam change, nothing in `PassFortKit`.

---

## What this delivers

The ⌘, window becomes preferences only, laid out as in the mockups:

| Tab | Contents |
|---|---|
| General | Lock after inactivity (with the sleep / screen-lock footer), Clear copied secrets after, Quick Access shortcut, Show in menu bar |
| Security *(needs unlock)* | Change Master Password…, Rotate… recovery key (with a confirmation) |
| Vault | Location, Show in Finder, Move…, Move Back to Default… |
| Backup | Destination (Show in Finder, Change…, Stop Using Folder), last backup and count, Back Up Now, on-lock toggle, Keep; an empty state with no folder |
| Sync | Status row with Sync Now · Devices with Add a Device… · Server (address, since, vault ID folded away) · Turn Off Sync… |

The operations that replace the vault move to the **File** menu: New Vault…, Open Vault…, Join
Synced Vault…, Restore from Backup…, and **Lock ⌘L** as a menu item (problem 1).

```
PassFort/
├── PassFortApp.swift                      P3 menu bar toggle · P4 Security tab · P5 File menu, presenters
├── Model/AppModel.swift                   P1 rotate / change password return the key · P4 drop cryptoStats · P5 sheet flags
├── Support/Pasteboard.swift               P2 clear-after preference
├── QuickAccess/QuickAccessController.swift P3 menu bar key
├── Features/Settings/
│   ├── SettingsView.swift                 P4 General only
│   ├── SecuritySettingsView.swift         P4 NEW — master password, recovery key
│   ├── LockedSettingsNotice.swift         P4 NEW — the one locked-state row (problem 4)
│   ├── ChangePasswordView.swift           P1 shows the new key in its own sheet
│   └── BackupSettingsView.swift           P6
├── Features/CreateVault/RecoveryKeyView.swift  P1 its content becomes RecoveryKeyPanel, shared
├── Features/Location/VaultLocationSettingsView.swift  P5
├── Features/Restore/RestoreBackupButton.swift  P5 becomes a flow modifier + a button
├── Features/Sync/SyncSettingsView.swift   P7
└── Backup/BackupModel.swift               P6 backup count
```

---

## Phase 0 — Branch and baseline

`git switch -c settings-redesign`; the plan and the review are its first commit.

**Checkpoint:** `xcodebuild test -scheme PassFort -destination 'platform=macOS'` passes on the
untouched branch, so any later failure is ours.

## Phase 1 — The new recovery key appears where the user is (problems 2, 3)

Today `rotateRecoveryKey` and `changePassword` park the open vault in `stagedRepo` and switch
`state` to `.showingRecoveryKey`, so `RootView` shows the key in the **main** window while the user is
in Settings — or nowhere, if the main window is closed. And `try?` drops a rotation failure.

- `AppModel.rotateRecoveryKey() -> Result<RecoveryKey, AppError>` and
  `changePassword(…) -> Result<RecoveryKey?, AppError>`. Both leave `state` at `.unlocked` and the
  vault open; the caller shows the key. `.showingRecoveryKey` stays for the two flows where no vault
  is open yet (first-run create and Start a New Vault), where the gate is the point.
- `RecoveryKeyPanel(key:onDone:)` — `RecoveryKeyView`'s content, shared. `RecoveryKeyView` wraps it
  for the main window; the Settings sheets use it directly.
- Rotate asks first (an alert naming what is lost), then shows the key in a sheet on the Settings
  window. A failure shows an error instead of doing nothing.
- `ChangePasswordView` switches to the panel inside its own sheet when a key comes back, the way
  `NewVaultView` switches to its "done" view. One sheet, so there is no second sheet to present
  after the first closes.
- On lock the sheets close and the key is dropped, as the main-window view is today.

**Why returned, not stored on the model:** the key is a secret that should live exactly as long as
the view showing it. A model property would outlive the sheet and need clearing on every path.

**Checkpoint:** app build and tests pass. `AppModelTests` changes:
`changePasswordWithANewRecoveryKeyReturnsItAndStaysUnlocked` (was `…ShowsItThenUnlocks`), plus a new
`rotateRecoveryKeyReturnsTheKeyAndStaysUnlocked` that also proves the new key opens the vault through
`VaultSession.openWithRecovery`.

## Phase 2 — Clear copied secrets after (a preference)

`Pasteboard.copyTransient` clears after a fixed 20 s. Add `Pasteboard.clearAfterKey`
(`clipboardClearSeconds`) and `Pasteboard.clearAfterSeconds` (stored value, default 20); the default
argument of `copyTransient` reads it, so the four callers don't change. Choices: 10 s, 20 s, 30 s,
1 minute, 2 minutes. No "Never": a secret on the clipboard is §3.2 A5's whole threat.

**Checkpoint:** tests pass; `PasteboardTests` gains `theDefaultDelayFollowsThePreference` (reads the
stored value, falls back to 20 for a missing or non-positive one).

## Phase 3 — Show in menu bar, and a Quick Access conflict message that helps

- `MenuBarExtra(isInserted:)` bound to `@AppStorage("showsMenuBarExtra")`, default on.
- The conflict line says what to do: Quick Access stays available from the menu bar icon and the
  Tools menu.

**Checkpoint:** builds; by hand, the toggle adds and removes the key icon at once.

## Phase 4 — Settings structure (problems 4, 5, 6)

- Every tab 500 pt wide, no `.padding()` around the grouped form.
- **General:** Locking (Lock after inactivity + "also locks when the Mac sleeps or the screen locks"),
  Clipboard (Phase 2), Quick Access (shortcut toggle, Show in menu bar). **Lock now** and **Crypto
  activity** go; `AppModel.cryptoStats()` goes with them (the CLI keeps `VaultRepository`'s).
- **Security** tab (new): Change Master Password…, recovery key Rotate…, footers from the mockup.
- `LockedSettingsNotice`: "PassFort is locked — unlock it to change these." plus **Unlock…**, which
  brings the main window forward. Used by Security and Sync; their controls dim beneath it. Vault and
  Backup work while locked and don't show it.
- Title case on every button.

**Checkpoint:** builds, tests pass; by hand, every tab is the same width and switching tabs doesn't
change it.

## Phase 5 — The File menu (problem 1)

- `CommandGroup(after: .newItem)`: New Vault…, Open Vault…, Join Synced Vault… (unlocked only),
  Restore from Backup… (whenever files may move, `allowsFileMoves`), then **Lock ⌘L** (unlocked
  only). The toolbar Lock button keeps its tooltip but loses its own ⌘L so there's one owner.
- The sheets are presented from the main window's root (`PassFortApp`), not `VaultListView`, so a
  vault swap that switches `RootView` to the recovery key doesn't tear the sheet down mid-flow.
- `RestoreBackupButton`'s picker and alerts become a `RestoreBackupFlow` modifier at the same root,
  driven by `AppModel.showingRestore`; the Unlock and Create screens' links set that flag.
- **Vault tab:** Location with Show in Finder, Move…, Move Back to Default…, its footer, and one row
  pointing at the File menu. The Replace section and its paragraph go.
- "Load Vault" is renamed **Open Vault** (menu, sheet title, button), the common Mac name. Texts that
  point at "Settings ▸ Vault" (Add a Device, Join, Sync's footer) point at the File menu instead.

**Checkpoint:** builds, tests pass; by hand, each File item opens its sheet, Lock ⌘L locks from any
PassFort window, and Restore works from the Unlock screen and from the menu.

## Phase 6 — Backup tab

- No folder: an empty state with one **Choose Folder…** (mockup).
- With a folder: Destination (name, Show in Finder, Change…, Stop Using Folder with "Backups already
  made stay in the folder"); Backups (last backup in relative time and how many are in the folder,
  Back Up Now; Back up when the vault locks; Keep). Restore moves to the File menu; the closing
  paragraph becomes the section footer.
- `BackupModel.backupCount`, refreshed after a run and when the tab appears, from
  `destination.list(vaultID:)` for the last backed-up vault. `nil` (unknown) shows nothing.

**Checkpoint:** tests pass; `BackupModelTests` gains `backupCountListsTheLastVaultsBackups`.

## Phase 7 — Sync tab

- **On:** Status row with Sync Now at its end; when paused after a hard problem, the row says so and
  offers **Details…** (the existing `SyncProblemSheet`). Devices with **Add a Device…** in the header;
  "This Mac" only as the badge. Server: address, Sync on since, Vault ID in a disclosure group with
  copy. A last row: "Every device keeps its own copy." and **Turn Off Sync…**.
- **Off:** server and enrollment secret, **Turn On Sync**, a three-sentence footer; the placeholder
  is `https://your-server/api/v1`.
- Locked: `LockedSettingsNotice` (Phase 4).

**Checkpoint:** builds, tests pass (`SyncStatusDisplayTests` unchanged).

## Phase 8 — Docs

README: the clipboard line (adjustable, 20 s by default) and Restore from Backup's new home. This
plan's row in the runbooks index becomes done, and `UI/settings-review.md` notes what was built.

**Checkpoint:** the README still follows the repo's user-facing shape.

---

## By-hand checks (the maintainer's)

1. Rotate from Settings ▸ Security with the main window closed: the confirmation, then the key,
   appear on the Settings window.
2. Change the master password with a new recovery key: the key appears in the same sheet.
3. Let auto-lock fire while a key is on screen: the sheet closes.
4. File ▸ Restore from Backup… while locked and while unlocked.
5. Turn Show in menu bar off and on; change Clear copied secrets after and copy a password.
6. Close every PassFort window, then choose File ▸ New Vault…: a vault window opens with the sheet.

## Outcome

Built as planned, with these differences, each checked against an offscreen render of every tab:

- The Quick Access row is a toggle, "Keyboard shortcut (⌃⌥Space)", not the mockup's recorder
  (deferred, below).
- The recovery-key row has no "Set" status (deferred, below); its footer says Rotate replaces the
  key or adds one.
- The Sync status keeps `SyncStatusDisplay`'s symbols (the sidebar footer's), not the mockup's
  green check, and "Turn Off Sync…" is a plain button: macOS colours destructive buttons only in
  menus and dialogs, and its confirmation dialog is destructive.
- The Unlock and Create screens keep their Restore from Backup link; it opens the same flow as the
  File menu.
- **New Vault… is in Settings ▸ Vault as well as the File menu** (the maintainer's call, after the
  build). It opens the same sheet on the vault window, brought forward, not on Settings: a new
  vault's recovery key appears in the vault window, which must not be left behind Settings. Open
  and Join stay in the File menu only.
- File-menu commands bring the vault window forward first, opening one if none is open, so the
  "no window open" case below is handled rather than deferred.

Two intermittent test failures turned up during the checkpoints. Neither comes from this work, and
each passed on rerun:

- **The test host exited mid-run** ("The test runner exited with code 0 before finishing"), failing
  whichever tests were running (twice, both `startNewVault` tests).
- **`QuickAccessTests.copyPutsTheChosenFieldOnTheBoardAndReportsAMissingOne`** once read an empty
  board after a copy. Likely cause: `Pasteboard` keeps one pending transient copy in static state,
  and any test calling `AppModel.lock()` in parallel runs `Pasteboard.clearTransient()`, which can
  clear that test's board at an `await`. **Fixed** afterwards: `Pasteboard` keeps one pending copy
  per pasteboard, and a lock clears `.general` plus the boards that model copied to.

## Deferred

- **A Quick Access shortcut recorder.** The shortcut stays fixed at ⌃⌥Space with an on/off toggle.
- **Recovery-key status ("Set").** Knowing whether the vault has a recovery slot means reading
  `slot_count`, and §5.3 has C++ alone decode the header: it needs a new `pf_header_*` seam function
  with seam fuzz and tests. Its own change, later.
