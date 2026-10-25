import AppKit
import Foundation
import Observation
import PassFortVault

/// The spine of the app: the lock-state machine. Every screen switches on
/// `state`. `repo` — and the decrypted `summaries` index (§3.4) — exist **only**
/// while `.unlocked`; `lock()` tears the whole graph down.
@MainActor @Observable
final class AppModel {
  enum State: Equatable {
    /// No vault file yet → the Create screen (Phase 4).
    case needsVault
    /// The Unlock screen, optionally showing the last failure.
    case locked(AppError? = nil)
    /// Argon2id in flight → a spinner.
    case unlocking
    /// A freshly created vault's recovery key, shown once. Blocks on the user
    /// confirming they wrote it down; `stagedRepo` holds the open vault meanwhile.
    case showingRecoveryKey(RecoveryKey)
    /// Unlocked; `repo` and `summaries` are live.
    case unlocked

    var isUnlocking: Bool { self == .unlocking }
  }

  private(set) var state: State
  /// Non-nil ONLY in `.unlocked`. Dropping it runs `VaultSession.deinit` →
  /// `pf_session_close`, which zeroizes RootKeys / DEK / subkeys.
  private(set) var repo: VaultRepository?
  /// The in-memory search index (§8.3) — decrypted titles, no secrets. Rebuilt on
  /// unlock, dropped on lock.
  private(set) var summaries: [AccountSummary] = []

  /// Whether the password generator sheet is up. Lives here so the Tools menu entry and the
  /// toolbar button open the same sheet; the generator needs no vault, so it works while locked.
  var showingGenerator = false
  /// Whether the import sheet is up (Tools menu, or the empty vault's button).
  var showingImport = false
  /// Whether the import-from-another-vault sheet is up (Tools menu, or the empty vault's button).
  var showingVaultImport = false

  private let service: VaultService
  private var autoLock: AutoLock?
  /// The open vault held between `createVault` and the recovery-key confirmation
  /// (so "repo is non-nil only in .unlocked" stays true during `.showingRecoveryKey`).
  /// Dropped by `lock()` like `repo` -- an auto-lock while the key is on screen must not leave
  /// an open session behind.
  private(set) var stagedRepo: VaultRepository?

  /// Sync for the open vault (`m5-sync.md` A.11): non-nil exactly while `repo` is, whether sync
  /// is on or off, so Settings can turn it on. Stopped and dropped by `lock()`.
  private(set) var sync: SyncController?
  /// Another device changed the master password or recovery key, and this unlock's password
  /// opened only the old header (A.8). Kept across a lock, so the Unlock screen can say so.
  private(set) var headerChangedElsewhere = false

  /// The last vault's sync, letting go of it after a lock. Every path that opens a vault waits
  /// for it first, so the old connection is closed before the file is opened again.
  private var retiringSync: Task<Void, Never>?

  private let syncAPI: SyncController.MakeAPI
  /// This Mac to the sync server; `nil` (the device file can't be read or written) leaves sync
  /// unavailable rather than registering a new device on every launch.
  private let device: DeviceIdentity?

  init(
    databasePath: String = VaultDatabase.defaultPath, highWaterURL: URL? = nil,
    syncAPI: @escaping SyncController.MakeAPI = SyncTransport.api,
    device: DeviceIdentity? = VaultService.storedDevice
  ) {
    self.service = VaultService(
      databasePath: databasePath, highWaterURL: highWaterURL,
      deviceID: device?.id ?? VaultService.deviceID)
    self.syncAPI = syncAPI
    self.device = device
    self.state = service.exists() ? .locked() : .needsVault
  }

  /// Whether this Mac can sync at all -- it has a stored device identity.
  var syncAvailable: Bool { device != nil }

  // MARK: - Transitions

  func unlock(password: Data) async {
    guard !state.isUnlocking else { return }  // the Unlock screen can double-submit
    state = .unlocking
    await retireSync()
    do {
      try await adoptUnlocked(service.unlock(password: password))
    } catch let error as AppError {
      state = .locked(error)
    } catch {
      state = .locked(.io(String(describing: error)))
    }
  }

  /// The GUI's `verify --accept-restore`: clear the anti-rollback mark, then retry.
  func acceptRestoreAndRetry(password: Data) async {
    try? await service.acceptRestoredBackup()
    await unlock(password: password)
  }

  /// First run: calibrate (off-main), create the vault, then either show the
  /// recovery key once or go straight to `.unlocked`. Returns the error on
  /// failure (state stays `.needsVault`); `nil` on success.
  @discardableResult
  func createVault(password: Data, recovery: Bool) async -> AppError? {
    guard case .needsVault = state else { return nil }
    await retireSync()
    do {
      let service = self.service
      let params = try await Task.detached(priority: .userInitiated) {
        try service.calibrate()
      }.value
      let (repo, key) = try await service.createVault(
        password: password, params: params, recovery: recovery)
      if let key {
        stagedRepo = repo
        state = .showingRecoveryKey(key)
      } else {
        try await adoptUnlocked(repo)
      }
      return nil
    } catch let error as AppError {
      return error
    } catch {
      return .io(String(describing: error))
    }
  }

  /// The user confirmed they wrote the recovery key down → finish unlocking.
  func confirmRecoveryKeyShown() async {
    guard case .showingRecoveryKey = state, let repo = stagedRepo else { return }
    stagedRepo = nil
    do {
      try await adoptUnlocked(repo)
    } catch {
      state = .locked(.io(String(describing: error)))
    }
  }

  func lock() {
    autoLock?.invalidate()
    autoLock = nil
    retire(sync)
    sync = nil
    repo = nil
    stagedRepo = nil
    summaries = []
    showingImport = false  // an import plan is plaintext; it must not reappear after unlock
    showingVaultImport = false
    Pasteboard.clearTransient()
    state = .locked()
  }

  /// `lock`, then wait until the vault's sync has let go of it too: after this nothing in the
  /// process holds the vault's files open, so they can be moved or replaced.
  func lockAndRelease() async {
    lock()
    await retireSync()
  }

  /// The vault files on disk were replaced behind the model's back (a restore): drop everything
  /// open and show the screen that matches what is there now -- Unlock if there is a vault,
  /// Create if there still is none.
  func reloadAfterRestore() {
    lock()
    headerChangedElsewhere = false  // the restored file may be another vault altogether
    state = service.exists() ? .locked() : .needsVault
  }

  // MARK: - Auto-lock

  /// The idle timeout, in seconds — a `UserDefaults` preference (`SettingsView`),
  /// not a secret. Defaults to 5 minutes.
  var autoLockSeconds: Int {
    let stored = UserDefaults.standard.integer(forKey: "autoLockSeconds")
    return stored > 0 ? stored : 300
  }

  /// Re-arm the auto-lock timer after the preference changes (from `SettingsView`).
  func autoLockSettingDidChange() {
    guard case .unlocked = state, repo != nil else { return }
    autoLock?.invalidate()
    autoLock = AutoLock(timeout: .seconds(autoLockSeconds)) { [weak self] in self?.lock() }
  }

  /// Rotate the recovery key (§5.6) — show it once, then back to `.unlocked`.
  func rotateRecoveryKey() async {
    guard case .unlocked = state, let repo else { return }
    guard let key = try? await repo.rotateRecoveryKey() else { return }
    sync?.localChange()  // the new header goes to the server (A.8)
    stagedRepo = repo
    state = .showingRecoveryKey(key)
  }

  /// Change the master password. On success with `issueRecoveryKey`, shows the new recovery key
  /// once (the old one stopped working either way). Returns the failure, or `nil`.
  func changePassword(current: Data, new: Data, issueRecoveryKey: Bool) async -> AppError? {
    guard case .unlocked = state, let repo else { return .io("The vault is locked.") }
    do {
      let key = try await repo.changePassword(
        current: current, new: new, issueRecoveryKey: issueRecoveryKey)
      sync?.localChange()  // the new header goes to the server (A.8)
      if let key {
        stagedRepo = repo
        state = .showingRecoveryKey(key)
      }
      return nil
    } catch {
      return VaultService.map(error)
    }
  }

  /// What replacing the vault needs from the rest of the app (the shape of `RestoreModel.Hooks`):
  /// no backup may read the vault's files while they are swapped.
  struct ReplaceVaultHooks {
    /// Called once the checks pass. Returns a reason to refuse (a backup is mid-run), or `nil` to
    /// go ahead.
    var begin: () -> String?
    /// Called last whenever `begin` went ahead, success or not.
    var end: () -> Void
  }

  /// Settings ▸ Vault ▸ Start a New Vault: check the current password, set the open vault's files
  /// aside (kept, never deleted), and create an empty vault in their place -- then show its
  /// recovery key once, or go straight to `.unlocked`, as on first run. Both Argon2id passes run
  /// before anything is touched.
  ///
  /// - Returns: the path the old vault was kept at, or why nothing changed.
  func startNewVault(
    current: Data, password: Data, recovery: Bool, _ hooks: ReplaceVaultHooks? = nil
  ) async -> Result<String, AppError> {
    let header: Data
    do {
      // Scoped so no strong reference to the open vault outlives this block (see `replaceVault`).
      guard case .unlocked = state, let repo else { return .failure(.io("The vault is locked.")) }
      header = try await repo.header()
    } catch {
      return .failure(VaultService.map(error))
    }

    let service = self.service
    let calibration = Task.detached(priority: .userInitiated) {
      try service.verifyPassword(current, header: header)
      return try service.calibrate()
    }
    do {
      _ = try await calibration.value
    } catch let error as AppError {
      return .failure(error)
    } catch {
      return .failure(VaultService.map(error))
    }

    return await replaceVault(label: "pre-new", hooks) {
      try await service.createVault(
        password: password, params: calibration.value, recovery: recovery)
    }
  }

  /// Settings ▸ Vault ▸ Load Vault: make the vault in `file` the live one. The file is copied, and
  /// the copy unlocked with `password` -- which also verifies its manifest -- before anything is
  /// swapped; then the open vault's files are set aside (kept, never deleted) and the copy takes
  /// their place. `file` itself is not changed.
  ///
  /// A copy of the open vault is refused: going back to an earlier copy is a restore, where the
  /// anti-rollback prompt belongs.
  ///
  /// - Returns: the path the old vault was kept at, or why nothing changed.
  func loadVault(
    from file: URL, password: Data, _ hooks: ReplaceVaultHooks? = nil
  ) async -> Result<String, AppError> {
    guard case .unlocked = state else { return .failure(.io("The vault is locked.")) }
    let service = self.service
    let staged: URL
    do {
      staged = try service.stageVault(from: file)
    } catch {
      return .failure(error as? AppError ?? .io(error.localizedDescription))
    }
    defer { service.discardStaged(staged) }

    let notAVault = AppError.loadRefused("That file isn't a PassFort vault.")
    do {
      try await service.checkVault(at: staged, password: password)
    } catch AppError.notAVault {
      return .failure(notAVault)
    } catch {
      return .failure(error as? AppError ?? VaultService.map(error))
    }
    guard let info = VaultBackup.inspect(staged) else { return .failure(notAVault) }
    if VaultBackup.inspect(URL(fileURLWithPath: service.databasePath))?.vaultID == info.vaultID {
      return .failure(
        .loadRefused(
          "That's this vault, or a copy of it. To go back to an earlier copy, use Restore from "
            + "Backup."))
    }

    return await replaceVault(label: "pre-load", hooks) {
      try service.install(staged, version: info.vaultVersion)
      return (try await service.unlock(password: password), nil)
    }
  }

  /// The swap both of those end in: release the open vault, set its files aside as
  /// `vault.sqlite.<label>-<time>`, and `install` another vault in their place. If `install`
  /// fails, the old files go back, so the old vault is never left hidden. Then show the new
  /// vault's recovery key once, or go straight to `.unlocked`.
  private func replaceVault(
    label: String, _ hooks: ReplaceVaultHooks?,
    install: () async throws -> (repo: VaultRepository, recoveryKey: RecoveryKey?)
  ) async -> Result<String, AppError> {
    // The checks before this took a second or more: the vault may have auto-locked meanwhile.
    guard case .unlocked = state else {
      return .failure(.io("The vault locked. Unlock it and try again."))
    }
    let hooks = hooks ?? ReplaceVaultHooks(begin: { nil }, end: {})  // nil: nothing to pause
    if let reason = hooks.begin() { return .failure(.notNow(reason)) }
    defer { hooks.end() }

    weak let released = repo
    await lockAndRelease()  // a sync run in flight holds the vault open
    // A spinner on the Unlock screen, and no unlock attempt while the files move.
    state = .unlocking
    await Task.yield()  // let the released vault's connection close before its files move
    // A connection still open on the old file would write its log beside the new vault.
    guard released == nil else {
      state = .locked()
      return .failure(.notNow("PassFort is still finishing with the vault. Try again in a moment."))
    }

    let aside: VaultService.SetAside
    let installed: (repo: VaultRepository, recoveryKey: RecoveryKey?)
    do {
      aside = try service.setAside(label: label)
    } catch {
      state = .locked()
      return .failure(error as? AppError ?? .io(error.localizedDescription))
    }
    do {
      installed = try await install()
    } catch {
      service.putBack(aside)
      state = .locked()
      return .failure(error as? AppError ?? .io(String(describing: error)))
    }

    let keptAt = aside.kept.path(percentEncoded: false)
    if let key = installed.recoveryKey {
      stagedRepo = installed.repo
      state = .showingRecoveryKey(key)
    } else {
      do {
        try await adoptUnlocked(installed.repo)
      } catch {
        // The new vault is in place; unlocking it retries.
        state = .locked(.io(String(describing: error)))
      }
    }
    return .success(keptAt)
  }

  /// Rebuild the summary index — call after a write.
  func refreshSummaries() async {
    guard let repo else { return }
    summaries = (try? await repo.summaries()) ?? summaries
  }

  /// Crypto op counts since unlock, for the Settings "under the hood" panel.
  /// `nil` while locked.
  func cryptoStats() async -> VaultRepository.CryptoStats? {
    await repo?.cryptoStats()
  }

  // MARK: - Sync

  /// First run (`.needsVault`): join a vault another device put on the sync server (A.11
  /// `join`) -- fetch its header, unlock it with `password`, build this Mac's vault on it, and
  /// let the first sync download every record. Returns why not, or `nil` on success.
  @discardableResult
  func joinVault(endpoint: URL, vaultID: UUID, password: Data) async -> AppError? {
    guard case .needsVault = state else { return nil }
    await retireSync()
    do {
      let api = try joinAPI(endpoint)
      try await adoptUnlocked(
        try await join(api, endpoint: endpoint, vaultID: vaultID, password: password))
      return nil
    } catch {
      return Self.joinFailure(error)
    }
  }

  /// Settings ▸ Vault ▸ Join a Synced Vault: as `joinVault`, in place of the open vault, whose
  /// files are set aside and kept -- they come back if the join fails. Each vault keeps its own
  /// sync settings in its file, so loading the old one again later resumes its sync.
  ///
  /// - Returns: the path the old vault was kept at, or why nothing changed.
  func joinVaultInPlace(
    endpoint: URL, vaultID: UUID, password: Data, _ hooks: ReplaceVaultHooks? = nil
  ) async -> Result<String, AppError> {
    let api: any SyncAPI
    do {
      api = try joinAPI(endpoint)  // refused before anything moves
    } catch {
      return .failure(Self.joinFailure(error))
    }
    return await replaceVault(label: "pre-join", hooks) {
      do {
        return (try await join(api, endpoint: endpoint, vaultID: vaultID, password: password), nil)
      } catch {
        throw Self.joinFailure(error)
      }
    }
  }

  /// The client to join through: refuses an insecure endpoint, or a Mac without a device identity.
  private func joinAPI(_ endpoint: URL) throws -> any SyncAPI {
    guard device != nil else {
      throw AppError.sync("PassFort can't store this Mac's device identity, so it can't sync.")
    }
    return try syncAPI(endpoint)
  }

  private func join(
    _ api: any SyncAPI, endpoint: URL, vaultID: UUID, password: Data
  ) async throws -> VaultRepository {
    try await service.join(api: api, endpoint: endpoint, vaultID: vaultID, password: password)
  }

  private static func joinFailure(_ error: Error) -> AppError {
    switch error {
    case let error as AppError: error
    case let error as SyncError: .sync(error.message)
    default: VaultService.map(error)  // a wrong password or a forged header: `.wrongPassword`
    }
  }

  /// Settle a conflict copy: keep it, keep the original, or keep both (A.11).
  func resolveConflict(
    copy id: UUID, _ resolution: VaultRepository.ConflictResolution
  ) async -> AppError? {
    await write { try await $0.resolveConflict(copy: id, resolution) }
  }

  // MARK: - Account reads

  /// The result of decrypting one account for a view.
  enum AccountLoad {
    case loaded(Account)
    /// No such row — compacted, or never existed.
    case missing
    /// The record would not open. The value is the sentence to show.
    case failed(String)
  }

  /// One `pf_open` for a detail or edit view. A record that fails to decrypt after the unlock-time
  /// manifest check passed was changed on disk while the vault was open; it is reported, never
  /// shown and never retried silently.
  func loadAccount(id: UUID) async -> AccountLoad {
    guard let repo else { return .failed(AppError.io("The vault is locked.").message) }
    do {
      guard let account = try await repo.account(id: id) else { return .missing }
      return .loaded(account)
    } catch {
      let mapped = VaultService.map(error)
      if mapped == .wrongPassword {
        return .failed(
          "This account failed its integrity check. It was changed outside PassFort and "
            + "can't be opened.")
      }
      return .failed(mapped.message)
    }
  }

  /// The password-health audit. Runs inside `VaultRepository`; only findings come back (§7.5).
  func audit() async -> Result<[AuditFinding], AppError> {
    guard let repo else { return .failure(.io("The vault is locked.")) }
    do {
      return .success(try await repo.audit())
    } catch {
      return .failure(VaultService.map(error))
    }
  }

  /// Unlock another PassFort vault read-only and read what it could bring in
  /// (`VaultImport.plan`). The plan is plaintext; the sheet holds it only while it is up, and
  /// `importAccounts` writes the chosen part.
  func planVaultImport(
    from file: URL, unlockingWith credential: VaultImport.Credential
  ) async -> Result<ImportPlan, AppError> {
    guard let repo else { return .failure(.io("The vault is locked.")) }
    do {
      return .success(
        try await service.planImport(
          fromVaultAt: file.path(percentEncoded: false), unlockingWith: credential, into: repo))
    } catch let error as AppError {
      return .failure(error)
    } catch {
      return .failure(.io(String(describing: error)))
    }
  }

  /// What Quick Access (and the sidebar menu) can put on the clipboard.
  enum CopyField: Equatable {
    case username, password, oneTimeCode

    var name: String {
      switch self {
      case .username: "username"
      case .password: "password"
      case .oneTimeCode: "one-time code"
      }
    }
  }

  /// Decrypt one account, put `field` on the clipboard as a transient copy (concealed, cleared
  /// after 20 s or on lock), and drop the plaintext. Returns why not, or `nil` on success.
  func copy(
    _ field: CopyField, from id: UUID, to board: NSPasteboard = .general
  ) async -> AppError? {
    let account: Account
    switch await loadAccount(id: id) {
    case .loaded(let loaded): account = loaded
    case .missing: return .io("That account no longer exists.")
    case .failed(let message): return .io(message)
    }
    let value: String?
    switch field {
    case .username: value = account.payload.username ?? account.payload.email
    case .password: value = account.payload.password
    case .oneTimeCode: value = account.payload.totp?.code()
    }
    guard let value, !value.isEmpty else {
      return .io("“\(account.payload.title)” has no \(field.name) saved.")
    }
    Pasteboard.copyTransient(value, to: board)
    return nil
  }

  // MARK: - Account writes

  /// Bumped after every account create / update / delete so a detail view knows
  /// to re-decrypt.
  private(set) var writeCounter = 0

  func createAccount(_ payload: AccountPayload) async -> AppError? {
    await write { _ = try await $0.create(payload) }
  }

  func updateAccount(id: UUID, to payload: AccountPayload) async -> AppError? {
    await write { try await $0.update(id: id) { $0 = payload } }
  }

  func deleteAccount(id: UUID) async -> AppError? {
    await write { try await $0.delete(id: id) }
  }

  /// Write imported accounts in one transaction -- all of them or none (`importAccounts`).
  func importAccounts(_ payloads: [AccountPayload]) async -> AppError? {
    await write { try await $0.importAccounts(payloads) }
  }

  /// Bring a deleted account back from Recently Deleted.
  func restoreAccount(id: UUID) async -> AppError? {
    await write { try await $0.restore(id: id) }
  }

  /// Erase every deleted account for good (`compact`). Backups made earlier still hold them.
  func emptyRecentlyDeleted() async -> AppError? {
    await write { try await $0.compact() }
  }

  /// Deleted accounts, most recently deleted first — the Recently Deleted list.
  var deletedSummaries: [AccountSummary] {
    summaries.filter(\.isDeleted).sorted { $0.lastUpdated > $1.lastUpdated }
  }

  private func write(_ body: (VaultRepository) async throws -> Void) async -> AppError? {
    guard let repo else { return .io("The vault is locked.") }
    do {
      try await body(repo)
      writeCounter &+= 1
      await refreshSummaries()
      sync?.localChange()
      return nil
    } catch VaultError.staleWrite {
      return .io("This account changed elsewhere. Reopen it and try again.")
    } catch {
      return .io(String(describing: error))
    }
  }

  // MARK: - Internal

  private func adoptUnlocked(_ repo: VaultRepository) async throws {
    let isNewSession = self.repo !== repo || sync == nil
    self.repo = repo
    self.summaries = try await repo.summaries()
    self.autoLock?.invalidate()
    self.autoLock = AutoLock(timeout: .seconds(autoLockSeconds)) { [weak self] in self?.lock() }
    self.state = .unlocked
    // Back from showing a rotated recovery key, the open vault -- and its sync -- carry on.
    guard isNewSession else { return }
    headerChangedElsewhere = (try? await repo.headerChangedElsewhere()) ?? false
    retire(sync)
    sync = device.map { device in
      SyncController(
        repository: repo, device: DeviceDTO(device, platform: .macos), makeAPI: syncAPI
      ) { [weak self] changed in
        await self?.syncDidRun(changed: changed)
      }
    }
    await sync?.start()
  }

  /// Stop `sync` now, and let it finish letting go of its vault in the background --
  /// `retireSync` waits for that.
  private func retire(_ sync: SyncController?) {
    guard let sync else { return }
    sync.cancel()
    let previous = retiringSync
    retiringSync = Task {
      await previous?.value
      await sync.stop()
    }
  }

  /// Wait until the previous vault's sync has let go of it.
  private func retireSync() async {
    await retiringSync?.value
    retiringSync = nil
  }

  /// After a sync run: rebuild the index if records changed, and pick up a header change another
  /// device made (A.8). A changed index bumps `writeCounter`, so an open detail view re-decrypts.
  private func syncDidRun(changed: Bool) async {
    guard let repo else { return }
    headerChangedElsewhere = (try? await repo.headerChangedElsewhere()) ?? headerChangedElsewhere
    guard changed, let fresh = try? await repo.summaries(), fresh != summaries else { return }
    summaries = fresh
    writeCounter &+= 1
  }
}
