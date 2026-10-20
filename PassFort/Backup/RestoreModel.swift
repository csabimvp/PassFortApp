import Foundation
import Observation
import PassFortVault

/// The file work of a restore, off the main actor.
nonisolated enum RestoreJob {
  struct Staged: Sendable, Equatable {
    let local: URL
    let info: VaultBackup.Info
  }

  /// Copy the picked backup to local disk and check it there. The share is only ever read as plain
  /// bytes: opening SQLite over SMB/NFS is not reliable (file locking), so every database
  /// operation in a restore happens on the local copy.
  @concurrent static func stage(_ picked: URL) async throws -> Staged {
    let fm = FileManager.default
    let scratch = fm.temporaryDirectory
      .appending(path: "passfort-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fm.createDirectory(
      at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

    let local = scratch.appending(path: picked.lastPathComponent)
    do {
      try fm.copyItem(at: picked, to: local)
    } catch {
      try? fm.removeItem(at: scratch)
      throw AppError.io(error.localizedDescription)
    }
    guard let info = VaultBackup.inspect(local) else {
      try? fm.removeItem(at: scratch)
      throw AppError.notABackup
    }
    return Staged(local: local, info: info)
  }

  /// - Returns: where the replaced vault was kept, or `nil` if there was none.
  @concurrent static func restore(
    _ staged: Staged, toDatabasePath databasePath: String, allowDifferentVault: Bool
  ) async throws -> URL? {
    do {
      return try VaultBackup.restore(
        from: staged.local, toDatabasePath: databasePath, allowDifferentVault: allowDifferentVault)
    } catch VaultBackup.Failure.notAVault {
      throw AppError.notABackup
    } catch VaultBackup.Failure.differentVault {
      throw AppError.io("That backup belongs to a different vault.")
    } catch {
      throw AppError.io(error.localizedDescription)
    }
  }

  static func discard(_ staged: Staged) {
    try? FileManager.default.removeItem(at: staged.local.deletingLastPathComponent())
  }
}

/// "Restore from Backup…": pick a file, see what it would do, confirm, swap. UI-free; the view
/// drives it and tests drive it directly.
///
/// Order matters and is enforced here: the vault is released (locked) *before* its files move, the
/// replaced vault is kept as `vault.sqlite.pre-restore-<time>` and never deleted, and the app
/// re-reads the disk afterwards. The next unlock then runs the normal anti-rollback check, so an
/// older backup surfaces the existing "this was a backup I restored" prompt.
@MainActor @Observable
final class RestoreModel {
  struct Candidate: Equatable {
    let staged: RestoreJob.Staged
    let fileName: String
    let madeAt: Date?
    /// The vault currently on this Mac, if any.
    let current: VaultBackup.Info?

    var backup: VaultBackup.Info { staged.info }
    var isDifferentVault: Bool { current.map { $0.vaultID != backup.vaultID } ?? false }
    var isOlderThanCurrent: Bool { current.map { backup.vaultVersion < $0.vaultVersion } ?? false }
  }

  enum Step: Equatable {
    case idle
    case staging
    case confirming(Candidate)
    case restoring
    /// Done. `previousVault` is the safety copy's file name, if there was a vault to replace.
    case restored(previousVault: String?)
    case failed(String)
  }

  /// What the restore needs from the rest of the app, as closures so tests can observe the order.
  struct Hooks {
    /// Called first. Returns a reason to refuse (e.g. a backup is mid-run), or `nil` to go ahead.
    var begin: () -> String?
    /// Close the open vault so its files can move.
    var releaseVault: () -> Void
    /// The files changed: re-read the disk and show the matching screen.
    var reload: () -> Void
    /// Called last, success or not.
    var end: () -> Void
  }

  private(set) var step: Step = .idle
  private let databasePath: String

  init(databasePath: String = VaultDatabase.defaultPath) {
    self.databasePath = databasePath
  }

  var isBusy: Bool { step == .staging || step == .restoring }

  /// A file was picked: copy it local, check it, and show what restoring it would do.
  func choose(_ picked: URL) async {
    guard !isBusy else { return }
    step = .staging
    do {
      let staged = try await RestoreJob.stage(picked)
      step = .confirming(
        Candidate(
          staged: staged, fileName: picked.lastPathComponent,
          madeAt: VaultBackup.date(inFileName: picked.lastPathComponent),
          current: VaultBackup.inspect(URL(fileURLWithPath: databasePath))))
    } catch {
      step = .failed((error as? AppError)?.message ?? AppError.io(error.localizedDescription).message)
    }
  }

  func cancel() {
    if case .confirming(let candidate) = step { RestoreJob.discard(candidate.staged) }
    step = .idle
  }

  /// Acknowledge a `.restored` / `.failed` result.
  func dismiss() {
    if case .restoring = step { return }
    step = .idle
  }

  /// The user confirmed. Replacing a *different* vault is allowed here because the confirmation
  /// they just gave names it (`Candidate.isDifferentVault`).
  func confirm(_ hooks: Hooks) async {
    guard case .confirming(let candidate) = step else { return }
    defer { RestoreJob.discard(candidate.staged) }

    if let reason = hooks.begin() {
      step = .failed(reason)
      return
    }
    defer { hooks.end() }

    step = .restoring
    hooks.releaseVault()
    await Task.yield()  // let the released vault's connection close before its files move

    do {
      let aside = try await RestoreJob.restore(
        candidate.staged, toDatabasePath: databasePath,
        allowDifferentVault: candidate.isDifferentVault)
      hooks.reload()
      step = .restored(previousVault: aside?.lastPathComponent)
    } catch {
      hooks.reload()  // the disk may or may not have changed; show what is really there
      step = .failed((error as? AppError)?.message ?? AppError.io(error.localizedDescription).message)
    }
  }
}
