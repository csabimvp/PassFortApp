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

  func lock() {
    autoLock?.invalidate()
    autoLock = nil
    repo = nil
    summaries = []
    state = .locked()
  }

  /// Rebuild the summary index — call after a write.
  func refreshSummaries() async {
    guard let repo else { return }
    summaries = (try? await repo.summaries()) ?? summaries
  }

  // MARK: - Internal

  private func adoptUnlocked(_ repo: VaultRepository) async throws {
    self.repo = repo
    self.summaries = try await repo.summaries()
    self.autoLock?.invalidate()
    self.autoLock = AutoLock { [weak self] in self?.lock() }
    self.state = .unlocked
  }
}
