# M3 addendum — Vault backup & restore

**Status:** In progress — Phases 0–2 done (2026-10-20); Phase 3 next. Follow top to bottom.
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

## Phase 3 — Settings UI: Backup section

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

---

## Phase 4 — Restore

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

---

## Phase 5 — Tests and CI

- `PassFortTests`: `BackupModel` with a fake `BackupDestination` (success, unavailable, stale bookmark,
  prune); `AppModel` restore transition; auto-backup-on-lock skips when version unchanged.
- CI already runs `swift test`; nothing to add except that `VaultBackupTests` must be in the
  explicit-coverage list the storage job prints (see `ci.yml`).
- Audit deliberately: no master password, key, or record plaintext in any log line or error string
  produced by this feature (project rule: no secret reaches a log).

---

## Phase 6 — Azure destination (deferred; blocked on M5)

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

## Where this leaves you

You can keep the live vault where it is, get a verified copy onto the NAS on every lock, and restore it
through the same anti-rollback path the CLI drill already uses. Azure slots in as a second destination
once M5's auth exists.

## Open questions

1. Backup filename scheme — timestamp only (above), or include the vault UUID so several vaults can share
   one NAS folder? (One vault today; cheap to add now, awkward later.)
2. Should the automatic backup also fire on a timer while unlocked (long sessions), or lock-only?
3. Keep-N: count-based only, or also "at least one per week for a month"? Count-based is the simple start.
