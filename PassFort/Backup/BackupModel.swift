import Foundation
import Observation
import PassFortVault

/// Everything one backup run does, off the main actor: check the vault, snapshot it locally,
/// hand the file to the destination, prune. Knows nothing about UI state.
nonisolated enum BackupJob {
  /// The last version successfully backed up, for the "skip if nothing changed" rule.
  struct Since: Sendable, Equatable {
    let vaultID: UUID
    let version: UInt64
  }

  struct Result: Sendable, Equatable {
    let date: Date
    let vaultID: UUID
    let version: UInt64
    let name: String
  }

  enum Outcome: Sendable, Equatable {
    case skippedUnchanged
    case backedUp(Result)
  }

  /// - Parameter skipIf: when the live vault is still exactly this version, do nothing.
  @concurrent static func run(
    databasePath: String, destination: any BackupDestination, keep: Int, skipIf since: Since?
  ) async throws -> Outcome {
    guard let current = VaultBackup.inspect(URL(fileURLWithPath: databasePath)) else {
      throw AppError.notAVault
    }
    if let since, since.vaultID == current.vaultID, since.version == current.vaultVersion {
      return .skippedUnchanged
    }

    let now = Date()
    let fileName = VaultBackup.fileName(vaultID: current.vaultID, at: now)
    let scratch = FileManager.default.temporaryDirectory
      .appending(path: "passfort-upload-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: scratch) }

    let local = scratch.appending(path: fileName)
    let info: VaultBackup.Info
    do {
      info = try VaultBackup.create(databasePath: databasePath, to: local)
    } catch VaultBackup.Failure.notAVault {
      throw AppError.notAVault
    }

    let stored = try await destination.store(local)
    // A prune failure must not turn a good backup into a failed one.
    _ = try? await destination.prune(vaultID: info.vaultID, keep: keep)

    return .backedUp(
      Result(date: now, vaultID: info.vaultID, version: info.vaultVersion, name: stored))
  }
}

/// The Settings ▸ Backup state: the chosen folder, the last run's outcome, and the rules for when
/// to run. UI-free and driven directly by tests; the real work is `BackupJob`.
///
/// Backup works on the sealed file, so it needs no unlock and no key: it runs just as well while
/// the vault is locked, which is exactly when the automatic one fires.
@MainActor @Observable
final class BackupModel {
  enum Status: Equatable {
    case idle
    case running
    case succeeded(Date, vaultVersion: UInt64)
    /// The message to show; persisted so a failed automatic backup is still visible after relaunch.
    case failed(String)
  }

  /// `UserDefaults` keys, shared with the Settings view's `@AppStorage`.
  enum Keys {
    static let onLock = "backup.onLock"
    static let keep = "backup.keep"
    static let lastDate = "backup.lastDate"
    static let lastVersion = "backup.lastVersion"
    static let lastVaultID = "backup.lastVaultID"
    static let lastFailure = "backup.lastFailure"
  }

  /// Latest only: each run stores and verifies the new file *before* pruning the old one, so there
  /// is never a moment without a good copy -- but there is no history either.
  static let defaultKeep = 1

  private(set) var status: Status
  private(set) var folderName: String?
  /// How many backups of the last backed-up vault the folder holds, for the Backup tab. `nil` until
  /// counted, with no folder or no backup yet, or when the folder can't be read.
  private(set) var backupCount: Int?

  private let databasePath: String
  private let destination: any BackupDestination
  private let bookmarks: any BookmarkStore
  private let defaults: UserDefaults

  init(
    databasePath: String = VaultDatabase.defaultPath,
    destination: any BackupDestination = FolderDestination(),
    bookmarks: any BookmarkStore = UserDefaultsBookmarkStore(),
    defaults: UserDefaults = .standard
  ) {
    self.databasePath = databasePath
    self.destination = destination
    self.bookmarks = bookmarks
    self.defaults = defaults
    self.status = Self.persistedStatus(in: defaults)
    self.folderName = destination.isConfigured ? destination.displayName : nil
  }

  var hasFolder: Bool { folderName != nil }
  var isRunning: Bool { status == .running }

  /// Where the NAS folder lives, as a hint for a restore file picker to open in.
  var folderURL: URL? { destination.isConfigured ? destination.folderURL : nil }

  /// Set while a restore swaps the vault files: no backup may read them mid-swap. The restore keeps
  /// the replaced vault as a safety copy, so skipping the lock-time backup loses nothing.
  private(set) var isPaused = false
  func setPaused(_ paused: Bool) { isPaused = paused }

  /// Back up automatically when the vault locks (on by default; inert until a folder is chosen).
  var backsUpOnLock: Bool {
    defaults.object(forKey: Keys.onLock) == nil ? true : defaults.bool(forKey: Keys.onLock)
  }

  var keep: Int {
    let stored = defaults.integer(forKey: Keys.keep)
    return stored > 0 ? stored : Self.defaultKeep
  }

  /// A failure the user hasn't seen resolved -- drives the note on the Unlock screen.
  var failureMessage: String? {
    if case .failed(let message) = status { return message }
    return nil
  }

  // MARK: - Folder

  /// Remember a folder the user just picked in an open panel (call while its grant is live).
  func setFolder(_ url: URL) throws {
    bookmarks.save(try FolderDestination.makeBookmark(for: url))
    folderName = destination.displayName
    defaults.removeObject(forKey: Keys.lastFailure)
    if case .failed = status { status = Self.persistedStatus(in: defaults) }
  }

  func removeFolder() {
    bookmarks.save(nil)
    folderName = nil
    backupCount = nil
  }

  /// Count the last backed-up vault's backups in the folder (`backupCount`). Called after each run
  /// and when the Backup tab appears; a folder that can't be read leaves the count unknown.
  func refreshCount() async {
    guard destination.isConfigured, let vaultID = lastBackup?.vaultID else {
      backupCount = nil
      return
    }
    backupCount = try? await destination.list(vaultID: vaultID).count
  }

  // MARK: - Running

  /// "Back Up Now". Always writes a new file, and reports every failure.
  func backUpNow() async { await run(manual: true) }

  /// Is `old -> new` a real lock -- the vault was open and now is not? A failed unlock attempt
  /// (`.unlocking -> .locked(error)`) and a repeated `.locked` are not.
  static func isLock(from old: AppModel.State, to new: AppModel.State) -> Bool {
    guard old == .unlocked, case .locked = new else { return false }
    return true
  }

  /// The vault just locked. Backs up only if the setting is on, a folder is chosen, and the vault
  /// changed since the last backup. Failures are recorded, never thrown: locking must not wait.
  func vaultDidLock() async {
    guard backsUpOnLock else { return }
    await run(manual: false)
  }

  private func run(manual: Bool) async {
    guard !isRunning, !isPaused else { return }
    guard destination.isConfigured else {
      if manual { fail(AppError.backupNotConfigured) }
      return
    }

    let previous = status
    status = .running
    let since: BackupJob.Since? =
      manual ? nil : lastBackup.map { BackupJob.Since(vaultID: $0.vaultID, version: $0.version) }

    do {
      let outcome = try await BackupJob.run(
        databasePath: databasePath, destination: destination, keep: keep, skipIf: since)
      switch outcome {
      case .skippedUnchanged:
        status = previous
      case .backedUp(let result):
        record(result)
        await refreshCount()
      }
    } catch {
      fail(error)
    }
  }

  // MARK: - Persistence

  private var lastBackup: (vaultID: UUID, version: UInt64)? {
    guard let raw = defaults.string(forKey: Keys.lastVaultID), let id = UUID(uuidString: raw),
      let stored = defaults.object(forKey: Keys.lastVersion) as? Int
    else { return nil }
    return (id, UInt64(max(stored, 0)))
  }

  private func record(_ result: BackupJob.Result) {
    defaults.set(result.date, forKey: Keys.lastDate)
    defaults.set(Int(clamping: result.version), forKey: Keys.lastVersion)
    defaults.set(result.vaultID.uuidString, forKey: Keys.lastVaultID)
    defaults.removeObject(forKey: Keys.lastFailure)
    status = .succeeded(result.date, vaultVersion: result.version)
  }

  private func fail(_ error: Error) {
    let message = (error as? AppError)?.message ?? AppError.io(error.localizedDescription).message
    defaults.set(message, forKey: Keys.lastFailure)
    status = .failed(message)
  }

  private static func persistedStatus(in defaults: UserDefaults) -> Status {
    if let message = defaults.string(forKey: Keys.lastFailure) { return .failed(message) }
    if let date = defaults.object(forKey: Keys.lastDate) as? Date {
      let version = UInt64(max(defaults.integer(forKey: Keys.lastVersion), 0))
      return .succeeded(date, vaultVersion: version)
    }
    return .idle
  }
}
