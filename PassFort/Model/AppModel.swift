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

  private let service: VaultService
  private var autoLock: AutoLock?
  /// The open vault held between `createVault` and the recovery-key confirmation
  /// (so "repo is non-nil only in .unlocked" stays true during `.showingRecoveryKey`).
  private var stagedRepo: VaultRepository?

  init(databasePath: String = VaultDatabase.defaultPath) {
    self.service = VaultService(databasePath: databasePath)
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
    summaries = []
    state = .locked()
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

  /// Rebuild the summary index — call after a write.
  func refreshSummaries() async {
    guard let repo else { return }
    summaries = (try? await repo.summaries()) ?? summaries
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
