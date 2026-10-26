# M3 addendum — Vault backup & restore

**Status:** Done apart from Phase 6 — Phases 0–5 and 7 built (2026-10-20); the by-hand checkpoints of Phases 3, 4 and 7 passed (2026-10-26). Phase 6 (Azure) is unblocked by M5 but not built.
**Prerequisite:** M3 Phases 1–8 done (the app runs, unlocks, edits, auto-locks). Independent of M4/M5, but
Phase 0 below says where it touches each.
**Spec:** `architecture.md` §5.5 (manifest / anti-rollback), §8.2 (WAL, `0600`, one live file), §9–§10
(sync, Azure), `m3-gui.md` (`VaultService.acceptRestoredBackup` — the restore hook already exists).

---

## What this delivers

A way to keep copies of the vault **off the Mac** and to get one back:

- **Back Up Now** — write a consistent, self-contained snapshot of the vault to a folder you chose
  (the NAS share).
- **Automatic backup on lock** — if the vault changed since the last backup.
- **Restore from backup…** — replace the live vault with a snapshot, safely.
- A **destination abstraction**, so Azure (Phase 6) is a second destination, not a rewrite.

### Decisions already made (do not re-litigate)

| Decision | Why |
|---|---|
| **One live vault, always local** (`~/Library/Containers/…/PassFort/vault.sqlite`). No "move the vault to the NAS", no vault switcher. | WAL needs shared-memory mmap and reliable locks; SMB/NFS give neither, so a live DB on a NAS can corrupt. §8.2 also says one file in Application Support. Multi-vault is a separate feature nobody asked for. |
| **The NAS and Azure are backup destinations only.** | Matches how it's actually used, and keeps the §8.2 write invariant on a local disk. |
| **A backup is a SQLite snapshot made with the online-backup API** (`DatabaseQueue.backup(to:)`), not a file copy. | A copy of `vault.sqlite` alone loses everything still in the `-wal`. The backup API reads through the WAL and yields one consistent, single file with no `-wal`/`-shm`. No checkpoint, no need to lock the app. |
| **Backups never include the high-water mark** (`.hw`, later the Keychain item). | The mark is local anti-rollback state. Restoring an old backup is exactly what it must notice; the existing `acceptRestoredBackup` path is the deliberate "yes, I meant to" step. |
| **Backups are as sensitive as the live file, no more.** | Records are sealed per-record, the header holds salt + KDF params only. A stolen backup is the same file-access adversary (§3.2) as a stolen vault; the master password and Argon2id are the protection. |
| **Backup/restore logic lives in `PassFortVault`; sandbox & UI live in the app.** | Testable with plain `swift test`; also gives the CLI backup/restore for free (and a cron job to the NAS, GUI closed). Per the M3 rule this is a package addition → own commit, with tests. |
| **No format change, no schema change, no ADR.** | A backup is an ordinary vault file. |

---

## Phase 0 — Spikes (30 min, throwaway)

Settle the two things the sandbox makes uncertain before writing real code.

1. **Can the sandboxed app write to the mounted share?** In a scratch SwiftUI view: `NSOpenPanel`
   (`canChooseDirectories = true`) → pick `/Volumes/<nas>/…` → `startAccessingSecurityScopedResource()`
   → write a file → create a **security-scoped bookmark**, quit, relaunch, resolve it, write again.
   Needs `ENABLE_USER_SELECTED_FILES = readwrite` (currently `readonly`, both configs) and, for app-scoped
   bookmarks, the `com.apple.security.files.bookmarks.app-scope` entitlement.
   - There is **no `.entitlements` file** in the project today. Create `PassFort/PassFort.entitlements`
     in Xcode (File ▸ New ▸ Property List) and point *Build Settings ▸ Code Signing Entitlements* at it.
     **Never hand-edit `project.pbxproj`** (`xcode.md`). M4 wants this file anyway.
   - A mounted SMB share is a kernel filesystem; it needs **no** `network.client` entitlement. Azure does
     (Phase 6).
2. **Does `DatabaseQueue.backup(to:)` do what we want on this GRDB (7.11.1)?** In `swift test` scratch:
   write rows, don't checkpoint, back up, open the copy, count rows; confirm no `-wal` beside it.

**Checkpoint:** a file lands on the NAS from the sandboxed app and still can after relaunch; the WAL-case
backup contains the latest row. If (1) fails, stop and rethink the destination UX (fallback: export via
`NSSavePanel` each time).

### Result — DONE (2026-10-20), both spikes passed

1. **Sandbox + NAS: works.** With `PassFort.entitlements` (`files.bookmarks.app-scope`) and
   `ENABLE_USER_SELECTED_FILES = readwrite`, the app wrote to `/Volumes/nas/Zeus/backups/` (SMB mount)
   straight after the open panel, saved a `.withSecurityScope` bookmark (900 bytes), and after a full
   quit + relaunch resolved it (`stale = false`) and wrote again. Write shape used: temp name in the
   destination, then `moveItem` into place. Not yet tested: the share being unmounted (Phase 2 must
   handle it; the spike did not exercise that path).
2. **Backup API: works, with one correction to Phase 1.** On a vault with five writes the live files were
   `vault.sqlite` 4 KB and `-wal` 115 KB, so nearly all data is in the WAL. A plain copy of
   `vault.sqlite` is **not even a readable vault**; `DatabaseQueue.backup(to:)` captured all five
   records. After `PRAGMA journal_mode = DELETE` on the snapshot, the main file **alone** unlocked with
   the password. A stray `-shm` can remain beside the snapshot, so **`VaultBackup.create` snapshots into
   a temp directory and ships only the main file** (Phase 1 reflects this).

---

## Phase 1 — `VaultBackup` in `PassFortVault` (own commit, with tests) — DONE (2026-10-20)

```swift
public struct BackupInfo: Sendable, Equatable {
  public let vaultVersion: UInt64   // from vault_meta
  public let manifestMAC: Data      // from vault_meta
  public let createdAt: Date
}

public enum VaultBackup {
  /// Snapshot `databasePath` into a new file at `destination`. Snapshots (backup API, then
  /// journal_mode = DELETE) inside a private temp directory, then moves **only the main file**
  /// into place -- any stray `-shm` stays behind and is removed with the temp dir -- so a
  /// half-written backup is never mistaken for a good one. Result is a single 0600 file.
  public static func create(databasePath: String, to destination: URL) throws -> BackupInfo

  /// Cheap structural check, no password: opens read-only, requires the §5.3 header row, reads
  /// vault_version + manifest_mac. nil = not a PassFort vault / corrupt.
  public static func inspect(_ url: URL) -> BackupInfo?

  /// Keep the newest `keep` files matching `passfort-vault-*.sqlite` in `folder`; never touches
  /// anything else in the folder.
  public static func prune(in folder: URL, keep: Int) throws

  /// Replace the live vault with `backup`. Moves the current files aside to
  /// `vault.sqlite.pre-restore-<timestamp>` (never deletes), installs the backup, and leaves the
  /// high-water mark alone -- the caller runs the existing accept-restore flow.
  public static func restore(from backup: URL, toDatabasePath: String) throws
}
```

Filename helper: `passfort-vault-<vault-uuid>-<UTC yyyyMMdd'T'HHmmss'Z'>.sqlite` (sortable; the UUID keeps
several vaults apart in one folder, and `prune` only ever touches the given vault's names).

### What shipped (deviations from the sketch above)

- API as built: `create(databasePath:to:) -> Info`, `inspect(_:) -> Info?`, `fileName(vaultID:at:)`,
  `prune(in:vaultID:keep:) -> [String]`, `restore(from:toDatabasePath:allowDifferentVault:now:) -> URL?`.
  `Info` is `{ vaultID, vaultVersion, manifestMAC }` (no `createdAt`: the timestamp lives in the name).
  Failures: `notAVault`, `destinationExists`, `differentVault(backup:live:)`.
- **The vault UUID is read from the header blob at byte offset 6** (after magic + `format_version`) in
  `VaultBackup.vaultID(inHeader:)`: the one place Swift looks inside the §5.3 header, which C++ otherwise
  owns. It is read-only, needs no password (a file-level backup must not), and is used for naming and a
  mismatch warning only; the unlock still authenticates the header. A test cross-checks it against
  `VaultSession.vaultUUID()`, so a header-layout change fails loudly instead of mislabelling files.
- `restore` refuses a backup of a different vault unless `allowDifferentVault`, which the sketch lacked.
- Backups are never overwritten (`destinationExists`); a same-second collision is the caller's to retry.
- Source is opened **read-only**, so backing up a non-vault can never create a schema in it.
- Not done: the `FaultHook` mid-write test. Replaced by a concurrent test (writes racing five backups,
  each backup then unlocked, which verifies the manifest MAC): a torn snapshot would fail it.

**Tests** (`PassFortVaultTests/VaultBackupTests.swift`):
- backup of a vault with un-checkpointed WAL contains the newest record (the regression this design
  exists for);
- backup is a single file; opens with `Vault.exists`, **unlocks with the master password**, and the
  manifest verifies;
- `inspect` rejects a random file, a truncated copy, and a bit-flipped header;
- backup taken *during* a write (reuse the `FaultHook` seam from `MidWriteKillTests`) is a consistent
  pre- or post-write state, never a torn one;
- `prune` keeps N newest, ignores foreign files, no-ops on a missing folder;
- restore round-trip: back up → write more → restore → old state, pre-restore files preserved,
  next unlock reports `rolledBack` until accept-restore, then succeeds.

**CLI (same commit series):** `passfort-cli backup <dir>` and `passfort-cli restore <file>`; add both to
`cli-guide.md`. A `launchd`/cron entry for the NAS then works with the GUI closed.

**Checkpoint:** `swift test` green; `passfort-cli backup /tmp/x` produces a file you can `restore` and
`unlock`.

---

## Phase 2 — Destination + sandbox plumbing (app target) — DONE (2026-10-20)

- `Backup/BackupDestination.swift`: `protocol BackupDestination { var name: String { get }; func
  store(_ file: URL) async throws; func list() async throws -> [URL]; func prune(keep: Int) async throws }`.
- `Backup/FolderDestination.swift`: holds the bookmark `Data`, resolves it (`.withSecurityScope`),
  brackets every operation in `start/stopAccessingSecurityScopedResource`, handles **stale bookmark**
  (re-resolve and re-save) and **share not mounted** (typed `AppError.backupDestinationUnavailable`,
  never a crash, never a silent skip).
- Persist the bookmark in `UserDefaults` (`backup.folderBookmark`) — it's a pointer, not a secret.
- Backup first goes to a temp file in the container, then is copied to the destination, so the NAS never
  sees a partial file and a flaky share can't leave the local vault in any state.

**Checkpoint:** unit-test `FolderDestination` against a temp dir; manual: unplug/unmount the share →
clear error, app keeps working.

### What shipped (deviations from the sketch above)

- `PassFort/Backup/BackupDestination.swift`: `store(_:) -> name`, `list(vaultID:) -> [names]`,
  `prune(vaultID:keep:) -> [removed]`, all `@concurrent` (the project's default-MainActor setting plus
  approachable concurrency would otherwise run blocking SMB I/O on the main actor). `list` returns
  names, not URLs: a URL inside a security scope is useless once the scope closes.
- `PassFort/Backup/FolderDestination.swift` + `BookmarkStore` (`UserDefaults` in the app, in-memory in
  tests). `isConfigured` and `displayName` for the Phase 3 status line. Choosing the folder (the
  `NSOpenPanel`) is UI and lands in Phase 3; Phase 2 only has `makeBookmark(for:)`.
- Two new `AppError` cases: `backupNotConfigured`, `backupDestinationUnavailable(folderName)`.
- **Read-back verification:** after the rename, `store` byte-compares the stored file with the local
  one and removes it if they differ. Deliberately plain bytes, not SQLite: file locking over SMB/NFS is
  not reliable.
- **The destination folder is never created.** A missing path reads as "unavailable"; recreating it
  would put a "backup" on the wrong volume when the share is unmounted.
- `startAccessingSecurityScopedResource() == false` is not treated as fatal (it also means "no scope
  needed"); real permission problems surface as file errors, mapped to `AppError.io`.
- Package addition (own commit): `VaultBackup.backups(in:vaultID:)`, newest first; `prune` builds on it.
- Tests (`PassFortTests/FolderDestinationTests.swift`, 8): intact store with no `.partial` left,
  never overwrites, missing source, stale partial replaced, not configured, **unmounted share**
  (folder deleted -> unavailable, not recreated), **moved folder** (bookmark follows and is refreshed,
  which exercises the stale path), list/prune scoped to one vault.
- Still manual: a real unmount of the NAS during a copy. Deleting a folder is the closest unit test;
  check this by hand in Phase 3 when Back Up Now exists.

---

## Phase 3 — Settings UI: Backup section — DONE (built 2026-10-20, checked by hand 2026-10-26)

In `SettingsView` (new `Section("Backup")`, works while locked too — backup needs no key):

- **Destination:** shows the folder name, **Choose Folder…** (NSOpenPanel) / **Remove**.
- **Back Up Now** — runs off the main actor; shows last-backup time + vault version, or the error.
- **Back up automatically when locking** toggle (`backup.onLock`) — only if
  `vault_version != lastBackedUpVersion` (stored in `UserDefaults`), so an idle vault doesn't churn files.
- **Keep the newest** picker (5 / 10 / 30; default 10) → `prune` after each successful backup.
- Status line, never a modal: "Last backup 14:02 · version 87 · NAS/PassFort".

State lives in a small `@Observable BackupModel` owned by `AppModel`'s environment, not in views. A
failed *automatic* backup surfaces as a badge in Settings and a one-line note on next unlock — it must
not block locking.

**Checkpoint:** Back Up Now writes a file on the NAS; edit an account, lock → a second file appears; edit
nothing, lock → no new file.

### What shipped (deviations from the sketch above)

- **A Settings *tab*, not a section in `SettingsView`.** `PassFortApp` wraps the Settings scene in a
  `TabView` (General | Backup). Done so `SettingsView` and `AppModel` stayed untouched while they had
  unrelated uncommitted work; the Backup state lives in its own `BackupModel`, injected from
  `PassFortApp`, not in `AppModel`.
- `Backup/BackupModel.swift`: `BackupJob` (nonisolated, `@concurrent`: inspect -> snapshot to a local
  temp dir -> `destination.store` -> prune -> clean up) and `@Observable BackupModel` (folder name,
  `Status` = idle | running | succeeded(date, version) | failed(message), the on-lock and keep
  settings, persisted last-success/last-failure in `UserDefaults`).
- `Features/Settings/BackupSettingsView.swift`: folder (NSOpenPanel), Back Up Now with a spinner, a
  status line, the on-lock toggle (default **on**, inert until a folder is chosen), keep **Latest only (default)** / 5 / 10 / 30. Latest-only still stores and verifies the new file *before* pruning the old one, so there is never a moment without a good copy; it just keeps no history.
- **The lock hook** is `.onChange(of: model.state)` in `PassFortApp`, firing only for
  `.unlocked -> .locked`. A wrong-password retry (`.unlocking -> .locked`) never triggers a backup.
- **Skip rule:** an automatic backup is skipped when the live vault is exactly the version (and vault
  id) last backed up; Back Up Now always writes. A *failed* run records nothing as "backed up", so the
  next lock retries even if the vault is unchanged.
- **Failures are never thrown at the lock.** They are recorded and persisted (`backup.lastFailure`),
  shown orange in the Backup tab and as one line on the Unlock screen (`UnlockView`, via an optional
  `BackupModel` environment so previews still work). A later success clears it.
- A prune failure after a good store is swallowed on purpose: it must not turn a good backup into a
  failed one.
- `BackupDestination` gained `isConfigured`.
- Tests (`PassFortTests/BackupModelTests.swift`, 12): filename carries the vault id, keep reaches
  prune, overlapping presses run one backup, skip-when-unchanged and re-backup-after-change, the
  toggle, no-folder (manual says so, automatic is silent), unavailable destination persists across a
  relaunch, success clears it, a failed lock backup is retried, no vault.
- **Not covered by tests, check by hand:** the NSOpenPanel flow, the TabView layout, and a real NAS.
  Checklist: (1) Settings ▸ Backup ▸ Choose Folder… on the share; (2) Back Up Now -> a file appears;
  (3) edit an account, lock -> a second file; (4) lock again with no edit -> no new file; (5) quit,
  relaunch, Back Up Now still works without re-choosing the folder; (6) disconnect the NAS, Back Up
  Now -> an orange "isn't available" message, app unaffected; lock -> the same note on the Unlock
  screen.

---

## Phase 4 — Restore — DONE (built 2026-10-20, checked by hand 2026-10-26)

Entry points: **Settings ▸ Restore from Backup…** and a link on the Unlock screen (the "my vault is gone"
case).

Flow:
1. Pick a file (NSOpenPanel on the destination folder by default).
2. `VaultBackup.inspect` — reject non-vaults; show "version 87, 20 Oct 14:02".
3. Confirm, with the real consequences: *"Replaces the current vault (version 91). Changes made after this
   backup will be lost. The current vault is kept as `vault.sqlite.pre-restore-…`."*
4. Lock, `VaultBackup.restore`, rebuild `AppModel` state → Unlock screen.
5. Unlock hits `rolledBack` (older version than the high-water mark) → the existing "I restored a backup"
   prompt → `acceptRestoredBackup`. **No new anti-rollback code;** if M4 has moved the mark to the
   Keychain, this goes through `HighWaterMarkStore` unchanged.

**Checkpoint:** the full drill — back up, add an account, restore, confirm the account is gone, the
pre-restore files exist, and unlock works after accept-restore.

### What shipped (deviations from the sketch above)

- **Where the button is.** `RestoreBackupButton` (own `RestoreModel`) appears on the **Unlock** screen,
  the **Create** screen ("Setting up a new Mac?" -- a Mac with no vault shows Create, not Unlock, so
  the sketch's Unlock-only link would have missed the main new-Mac case) and **Settings ▸ Backup ▸
  Restore**. Disabled while a vault is being created or unlocked.
- **The picked file is never opened over the network.** `RestoreJob.stage` copies it to a local temp
  dir as plain bytes and every SQLite operation (inspect, restore) uses that copy; the share only ever
  sees byte reads, the same rule as the backup read-back. The staged copy is deleted on cancel, success
  and failure.
- **Order is enforced in `RestoreModel.confirm`**: `begin` (may refuse) -> `releaseVault` -> yield ->
  swap -> `reload` -> `end`. `reload` also runs after a failed swap, so the screen always matches the
  disk. Tested by recording the hook order and the version on disk at the moment of `reload`.
- **Auto-backup is paused during a restore** (`BackupModel.setPaused`) and a restore refuses to start
  while a backup is running. Without this, releasing the vault fires the lock-time backup concurrently
  with the file swap. Skipping it loses nothing: the replaced vault is kept as a safety copy.
- **`AppModel.reloadAfterRestore()`** (new): release anything open, then `.locked()` if a vault exists
  on disk, `.needsVault` if not. Needed for the fresh-Mac case, where `lock()` alone would land on the
  wrong screen.
- The confirmation names what matters: backup date (parsed from the file name via
  `VaultBackup.date(inFileName:)`) and version vs. the vault on this Mac, "older: later changes will be
  missing", a loud line for a **different vault**, and that **the restored vault opens with the master
  password it had when the backup was made** (it may not be your current one).
- Anti-rollback: unchanged. Restoring an older backup makes the next unlock show the existing "This was
  a backup I restored" prompt; no new rollback code.
- Tests (`RestoreModelTests`, 9; + `AppModelTests.reloadAfterRestore…`, + a `BackupModel` pause test).
- **Check by hand:** (1) back up, add an account, lock; (2) Settings ▸ Backup ▸ Restore from Backup…,
  pick the file -- the dialog shows its date and version; (3) Restore -> the Unlock screen; unlock ->
  the "backup I restored" prompt -> accept -> the account you added is gone; (4) the safety copy
  `vault.sqlite.pre-restore-…` exists in the app's PassFort folder; (5) restore from the **Create**
  screen on a fresh vault location (rename the vault folder away first, then put it back).

---

## Phase 5 — Tests and CI — DONE (2026-10-20)

- `PassFortTests`: `BackupModel` with a fake `BackupDestination` (success, unavailable, stale bookmark,
  prune); `AppModel` restore transition; auto-backup-on-lock skips when version unchanged.
- CI already runs `swift test`; nothing to add except that `VaultBackupTests` must be in the
  explicit-coverage list the storage job prints (see `ci.yml`).
- Audit deliberately: no master password, key, or record plaintext in any log line or error string
  produced by this feature (project rule: no secret reaches a log).

### What shipped (and what the audit found)

- **CI would have failed.** `ci.yml` runs `swift format lint --strict --recursive Sources Tests` on the
  package; four lines in `VaultBackup.swift` / `VaultBackupTests.swift` exceeded the length limit
  (nobody had run the linter). Fixed with `swift format format --in-place` on those two files only;
  lint is clean. **Run `swift format lint --strict --recursive Sources Tests` from
  `Packages/PassFortKit` before committing package code.**
- **App tests unsigned.** CI runs `xcodebuild test … CODE_SIGNING_ALLOWED=NO` (no sandbox, no
  entitlements). Run locally with that flag: all green, including the security-scoped-bookmark tests.
- **Secrets-in-logs audit: clean.** There is no `print` / `NSLog` / `os_log` / `Logger` / `dump` call
  anywhere in `PassFort/` or `PassFortVault`'s sources (the CLI's `print` output is its UI, to the
  user's terminal). Backup/restore error text carries file names and `localizedDescription` only,
  never keys, passwords or record contents.
- **Test: a backup contains no plaintext** (`aBackupContainsNoPlaintextAndNoAntiRollbackMark`): a
  vault with distinctive title/username/password is backed up; none of them, nor the master password,
  appears in the bytes, and the backup folder holds only the one file (no `.hw`).
- **Test: what counts as a lock** (`BackupModel.isLock(from:to:)`, now what `PassFortApp` calls): only
  `.unlocked -> .locked`; a wrong-password retry, a repeated `.locked`, `.unlocking`, the recovery-key
  screen and `.needsVault` never trigger a backup. This was previously a comment in `PassFortApp`.
- `ci.yml` needs no new step: `swift test` already runs `VaultBackupTests` and `xcodebuild test` runs
  the app suites. Its comment listing what `swift test` covers now mentions the backup suite.
- Already covered in Phases 3–4 and not repeated: `BackupModel` with a fake destination, the
  `AppModel` restore transition, skip-when-unchanged.

---

## Phase 6 — Azure destination (deferred; blocked on M5)

> **Unblocked (2026-10-25): M5 is done.** It's still not built, and it isn't part of M5. When it is
> built, it reuses the `k_auth` session as it shipped (`POST /vaults/{id}/session`, a 15-minute
> token sent as `X-PassFort-Token`). It gets its own endpoint, `PUT /v1/vaults/{id}/backups`, as a
> contract change in `SyncAPI/openapi.yaml` first, then in `PassFortCloud`. The network
> entitlement below is already in `PassFort.entitlements` (M5 Phase 13). Blob Storage adds a
> resource to `main.bicep`, so check the cost brief (`architecture.md` §10.1) before adding it.

**Don't build until M5 has working auth** (`m5-sync.md`, `architecture.md` §10.4). Notes so the earlier
phases don't paint us into a corner:

- **Sync is not backup.** M5 replicates writes — including a mistaken delete or a corrupted record —
  to the server within seconds. A backup is a *point-in-time* copy. So don't treat "we have sync" as
  "we have off-site backup". Recommended: a separate **whole-file snapshot** destination.
- `AzureBlobDestination: BackupDestination` uploads the same backup file (already sealed; Azure learns
  nothing beyond what it already learns from sync) to a private Blob container, **with blob versioning
  and soft-delete on** and a lifecycle rule that expires old snapshots. Costs cents/month at this size
  (§10.1).
- Auth: reuse the M5 device/vault auth against a thin Function, e.g. `PUT /v1/vaults/{id}/backups`,
  rather than a long-lived storage key in the app (open decision 13 in `architecture.md` §14 already
  leans the same way).
- Needs `com.apple.security.network.client` in `PassFort.entitlements`.
- UI: a second "Destinations" row in the Backup section; both destinations run on Back Up Now / on lock.
- Open: bring Azure backup under ADR-0005 as an amendment, or a new ADR — decide when M5 auth lands.

---

## Phase 7 — Choose where the live vault lives — DONE (built 2026-10-20, checked by hand 2026-10-26)

The backup folder is chosen in Settings; the same choice for the **live** vault ("put it on my
external drive / in a folder I pick") reverses the first decision in this document ("one live vault,
always local"), so it is planned here and not built until the two decisions at the end are made.

### What the live vault can and can't live on

| Location | Verdict | Why |
|---|---|---|
| A folder on an internal or external **local** volume | allowed | SQLite + WAL are fine on a local filesystem |
| A mounted **network** share (SMB/NFS: the NAS) | refused | WAL needs shared memory and reliable locks; that is how a vault gets corrupted. Detect with `URLResourceKey.volumeIsLocalKey == false`. The NAS stays a *backup* destination. |
| A **cloud-synced** folder (iCloud Drive, Dropbox, OneDrive, Google Drive: `~/Library/CloudStorage/…`, `~/Library/Mobile Documents/…`) | refused | A sync client rewriting `-wal`/`-shm`/the main file under a live SQLite connection corrupts it. Refuse with a plain explanation rather than warn. |

### Design

1. **Moving is a copy-verify-switch, never a bare pointer change.** Two vault files with a stored
   pointer between them diverge silently. "Move Vault…" runs: lock -> `VaultBackup.create` into a
   local temp dir (WAL-safe) -> `VaultBackup.restore(from:toDatabasePath:)` onto
   `<chosen>/PassFort/vault.sqlite` (already tested; moves anything already there aside, refuses a
   *different* vault) -> `inspect` the result and require the same vault id, `vault_version` and
   manifest MAC -> only then save the new location -> move the old files aside as
   `vault.sqlite.pre-move-<time>` (kept, never deleted) -> ask the user to quit and reopen. "Use
   Default Location" is the same operation in the other direction.
2. **The location is a security-scoped bookmark** in `UserDefaults` (same entitlements as the backup
   folder, nothing new). It is resolved **once at launch**, before `AppModel` is created, and its scope
   is held open for the whole session (the `-wal`/`-shm` files live in that folder). A new
   `VaultLocation` type owns resolve / scope / move.
3. **Takes effect after a relaunch.** `AppModel`, `BackupModel` and `RestoreModel` all take their
   `databasePath` at construction. Rebuilding them live is a larger and riskier change than one
   "Quit PassFort" button, so the move finishes with that button.
4. **A configured-but-unreachable location is its own screen**, never "Create a vault". Today
   `.needsVault` means "no file": if the external drive is unplugged and the app fell through to
   Create, it would make a second, empty vault in the default location. A `VaultLocationUnavailable`
   screen (Retry / Choose Another Location / Use Default Location) is shown instead, decided before
   `RootView` in `PassFortApp`.
5. **The anti-rollback mark stays on this Mac.** Today it is `<db>.hw` beside the vault; in a chosen
   folder that would travel with the folder, and a restored old folder would restore an old mark with
   it, defeating the check. For a non-default location the mark lives in the app container keyed by
   vault UUID (`HighWaterMark(url:)` already exists). This needs `Vault.create/unlock/…` to accept an
   optional `highWater:` (default unchanged), a small `PassFortVault` change with tests, and a one-time
   copy of the current mark on a move. M4 Phase 3 moves the mark to the Keychain anyway; this is
   compatible with it.
6. Backup and restore follow the location automatically (they already take `databasePath`); a backup
   made from the live vault in a custom folder is identical to one from the default.

### Phases

- 7a `VaultLocation` + local-volume / cloud-folder checks + tests (temp dirs; a fake "remote" volume
  check behind a protocol).
- 7b `PassFortVault`: optional `highWater:` on `Vault.create/createWithRecovery/recover/unlock` + tests.
- 7c Launch wiring in `PassFortApp` and the unavailable-location screen.
- 7d Settings ▸ General ▸ "Vault location": show the path, **Move Vault…**, **Use Default Location**,
  the quit-and-reopen step.
- 7e Tests for the move (round trip, different-vault refusal, same-version/MAC verification failure
  leaves the old vault active, interrupted move) and a by-hand checklist (external drive unplugged at
  launch; moving there and back).

### Decisions (made 2026-10-20)

1. **Local folders only.** The NAS and cloud-synced folders are refused for the live vault (they stay
   valid *backup* destinations).
2. **A move takes effect after a relaunch.** The move ends on a blocking "Restart to finish" screen.

### What shipped (deviations from the plan above)

- **7a** `Location/VaultLocation.swift`: `LocationProblem` + `SystemFolderChecker` (not a folder, not
  writable, `volumeIsLocal == false` -> network, `/Library/CloudStorage`, `/Library/Mobile Documents`,
  `com~apple~CloudDocs` or an iCloud-ubiquitous item -> synced), `VaultLocationRecord`/`Store`
  (bookmark + path, `UserDefaults`), and `VaultLocation.resolveAtLaunch` -> `.standard | .custom |
  .unavailable`. For a chosen folder it opens the security scope and **never closes it** (the `-wal` /
  `-shm` live there for the whole run). The vault sits in `<chosen>/PassFort/vault.sqlite`.
- **7b** (package) `Vault.create / createWithRecovery / recover / unlock` take an optional
  `highWater:`; default unchanged, so the CLI is unaffected.
  **Found by the tests:** `HighWaterMark.write` failed when its folder did not exist, and the app only
  worked because launch happened to create the folder first. `write` now creates its own folder
  (package commit `60e17be`), and the duplicate `mkdir` calls in launch and the mover were removed.
- **7c** `PassFortApp.init` resolves the location once, before anything opens the vault, and builds
  `AppModel(databasePath:highWaterURL:)`, `BackupModel` and the location model from it. `VaultService`
  and `AppModel.init` gained `highWaterURL` (default `nil`: unchanged). `RestoreBackupButton` now takes
  its path from the location, so a restore targets the vault actually in use. The window shows
  `VaultLocationUnavailableView` for an unreachable folder (never "Create a vault") and
  `RelaunchRequiredView` after a move.
- **7d** A **Vault** tab in Settings (General | Vault | Backup): the path, **Move Vault…** (folder
  picker -> confirmation -> move), **Use Default Location**, the result, and **Restart PassFort**.
  The "unavailable" screen offers *Restart and Try Again*, *Choose Another Folder…* and *Use Default
  Location* (both pointer-only: nothing can be copied from a drive that is not there; the confirmation
  says what happens if the chosen folder holds no vault).
- **The order is copy -> verify -> switch the pointer -> retire the old files** (`VaultMover.copy`,
  `store.save`, `VaultMover.retire`). Verification requires the same vault id, `vault_version` and
  manifest MAC. The anti-rollback mark is carried to the new location and never lowered. A different
  vault already at the target is refused; an older copy of the same vault there is set aside, kept.
  Old files become `vault.sqlite.pre-move-<time>` (+ `-wal`/`-shm`), never deleted.
- After a successful move, backups stay **paused** and the vault stays locked: this process still
  points at the old place, so the app shows only the restart screen.
- Tests: `VaultLocationTests` (18), `VaultMoverTests` (10), `VaultLocationModelTests` (9, including
  `AppModel` keeping its mark where it was told), `VaultHighWaterLocationTests` (6, package).
- **Not covered by tests:** (1) the "copy did not verify" rollback in `VaultMover` (nothing can force a
  verification failure; the code path is small and reviewed, but unexercised); (2) real
  `volumeIsLocal == false` detection on an SMB mount (the unit tests use a fake checker; the NAS was
  not mounted); (3) the open panels, alerts and the relaunch button.

### Check by hand

1. **Settings ▸ Vault** shows the default path. **Move Vault…**, pick a folder on an attached drive or
   in Documents; the confirmation names it; **Move Vault** -> the "Restart to finish" screen.
2. **Restart PassFort.** Unlock with the usual password; your accounts are all there. Settings ▸ Vault
   shows the new path and "A folder you chose". The old file sits beside the old location as
   `vault.sqlite.pre-move-…`.
3. Edit an account, lock, restart: the edit survived (it was written to the new vault).
4. **Network drive refused:** with the NAS mounted, Move Vault… to a folder on it -> "That folder is on a
   network drive…". This is the real test of the volume check.
5. **Synced folder refused:** pick a folder inside Dropbox/iCloud Drive -> the "synced" message.
6. **Unavailable:** with the vault on an external drive, quit, eject the drive, relaunch -> "Your vault
   isn't available", never Create. Reconnect, **Restart and Try Again** -> normal unlock.
7. **Back:** Settings ▸ Vault ▸ **Use Default Location** -> restart -> unlock; the vault is in
   PassFort's own storage again and Settings shows "PassFort's own storage".
8. **Backup and Restore still work** from the new location (Back Up Now; Restore replaces the vault
   that is actually in use).
---

## Where this leaves you

You can keep the live vault where it is, get a verified copy onto the NAS on every lock, and restore it
through the same anti-rollback path the CLI drill already uses. Azure slots in as a second destination
once M5's auth exists.

## Open questions — all settled (2026-10-21)

1. **Backup filename scheme — decided and shipped:** `passfort-vault-<vault-uuid>-<UTC timestamp>.sqlite`,
   so several vaults can share one folder (`VaultBackup.fileName`).
2. **Timer-based backup while unlocked — no.** Backup is on lock plus Back Up Now. A timer is scope
   the app doesn't need: an unlocked session is bounded by auto-lock, which triggers the lock backup.
   Revisit only if long unlocked sessions turn out to lose real work.
3. **Keep-N — count-based only, shipped:** Latest only (default) / 5 / 10 / 30, pruned after the new
   file is stored and verified. A "one per week" rule is not built.
