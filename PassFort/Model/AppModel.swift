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

  init(databasePath: String = VaultDatabase.defaultPath, highWaterURL: URL? = nil) {
    self.service = VaultService(databasePath: databasePath, highWaterURL: highWaterURL)
    self.state = service.exists() ? .locked() : .needsVault
  }

  // MARK: - Transitions

  func unlock(password: Data) async {
    guard !state.isUnlocking else { return }  // the Unlock screen can double-submit
    state = .unlocking
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
    try? service.acceptRestoredBackup()
    await unlock(password: password)
  }

  /// First run: calibrate (off-main), create the vault, then either show the
  /// recovery key once or go straight to `.unlocked`. Returns the error on
  /// failure (state stays `.needsVault`); `nil` on success.
  @discardableResult
  func createVault(password: Data, recovery: Bool) async -> AppError? {
    guard case .needsVault = state else { return nil }
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
    repo = nil
    stagedRepo = nil
    summaries = []
    showingImport = false  // an import plan is plaintext; it must not reappear after unlock
    showingVaultImport = false
    Pasteboard.clearTransient()
    state = .locked()
  }

  /// The vault files on disk were replaced behind the model's back (a restore): drop everything
  /// open and show the screen that matches what is there now -- Unlock if there is a vault,
  /// Create if there still is none.
  func reloadAfterRestore() {
    lock()
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
    stagedRepo = repo
    state = .showingRecoveryKey(key)
  }

  /// Change the master password. On success with `issueRecoveryKey`, shows the new recovery key
  /// once (the old one stopped working either way). Returns the failure, or `nil`.
  func changePassword(current: Data, new: Data, issueRecoveryKey: Bool) async -> AppError? {
    guard case .unlocked = state, let repo else { return .io("The vault is locked.") }
    do {
      if let key = try await repo.changePassword(
        current: current, new: new, issueRecoveryKey: issueRecoveryKey)
      {
        stagedRepo = repo
        state = .showingRecoveryKey(key)
      }
      return nil
    } catch {
      return VaultService.map(error)
    }
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
      return nil
    } catch VaultError.staleWrite {
      return .io("This account changed elsewhere. Reopen it and try again.")
    } catch {
      return .io(String(describing: error))
    }
  }

  // MARK: - Internal

  private func adoptUnlocked(_ repo: VaultRepository) async throws {
    self.repo = repo
    self.summaries = try await repo.summaries()
    self.autoLock?.invalidate()
    self.autoLock = AutoLock(timeout: .seconds(autoLockSeconds)) { [weak self] in self?.lock() }
    self.state = .unlocked
  }
}
