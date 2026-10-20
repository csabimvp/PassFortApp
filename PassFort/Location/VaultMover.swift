import Foundation
import PassFortVault

/// The file work of moving the live vault between locations, off the main actor.
///
/// A move is **copy, verify, switch, retire** and never a bare pointer change: two vault files with
/// a stored pointer between them diverge silently. This type does the first and last steps; the
/// caller switches the pointer in between, so a failure anywhere before that leaves the old vault
/// in place and still active.
nonisolated enum VaultMover {
  struct Endpoint: Sendable, Equatable {
    let databasePath: String
    /// `nil` is the default: the `<db>.hw` sidecar beside the vault.
    let highWaterURL: URL?

    var highWater: HighWaterMark {
      highWaterURL.map(HighWaterMark.init(url:)) ?? HighWaterMark(sidecarFor: databasePath)
    }
  }

  struct Copied: Sendable, Equatable {
    /// What was copied; `nil` when there was no vault to copy (a pointer-only change).
    let info: VaultBackup.Info?
    /// A different file that was at the target and was set aside, if any (kept, never deleted).
    let replacedAside: String?
  }

  /// Copy the vault at `source` to `target`, verify the copy, and carry the anti-rollback mark.
  ///
  /// - Parameter source: `nil` when the old location can't be read at all (an unplugged drive); the
  ///   change is then pointer-only and the target is expected to hold the vault already, or none.
  /// - Throws: `AppError` -- nothing at the old location is touched, and the target is rolled back
  ///   to how it was.
  @concurrent static func copy(from source: Endpoint?, to target: Endpoint) async throws -> Copied {
    let fm = FileManager.default
    if source?.databasePath == target.databasePath {
      throw AppError.locationNotAllowed("The vault is already there.")
    }
    guard let source, fm.fileExists(atPath: source.databasePath) else {
      return Copied(info: nil, replacedAside: nil)
    }

    let scratch = fm.temporaryDirectory
      .appending(path: "passfort-move-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fm.createDirectory(
      at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: scratch) }

    let snapshot = scratch.appending(path: "vault.sqlite")
    let info: VaultBackup.Info
    do {
      info = try VaultBackup.create(databasePath: source.databasePath, to: snapshot)
    } catch VaultBackup.Failure.notAVault {
      throw AppError.notAVault
    } catch {
      throw AppError.io(error.localizedDescription)
    }

    let aside: URL?
    do {
      aside = try VaultBackup.restore(from: snapshot, toDatabasePath: target.databasePath)
    } catch VaultBackup.Failure.differentVault {
      throw AppError.locationNotAllowed(
        "That folder already holds a different PassFort vault. Choose another folder.")
    } catch {
      throw AppError.io(error.localizedDescription)
    }

    // Trust nothing: the file that will be opened at the next launch must be this vault, this version.
    guard VaultBackup.inspect(URL(fileURLWithPath: target.databasePath)) == info else {
      undoInstall(at: target.databasePath, restoring: aside)
      throw AppError.io("The copy didn't verify, so nothing was changed.")
    }

    do {
      if let markURL = target.highWaterURL {
        try fm.createDirectory(
          at: markURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      }
      // Never lower a mark that is already further ahead at the target.
      let carried = try max(source.highWater.read(), target.highWater.read())
      try target.highWater.write(carried)
    } catch {
      undoInstall(at: target.databasePath, restoring: aside)
      throw AppError.io(error.localizedDescription)
    }
    return Copied(info: info, replacedAside: aside?.lastPathComponent)
  }

  /// Set the old vault's files aside as `vault.sqlite.pre-move-<time>` (+ `-wal`/`-shm`), kept and
  /// never deleted. Best effort and called only after the pointer switched: if it fails, the old
  /// files merely stay where they were, unused.
  ///
  /// - Returns: the name the main file was kept under, or `nil` if there was nothing to move.
  static func retire(_ source: Endpoint, now: Date = .now) -> String? {
    let fm = FileManager.default
    let aside = source.databasePath + ".pre-move-\(stamp(now))"
    var kept: String?
    for suffix in ["", "-wal", "-shm"] {
      let from = source.databasePath + suffix
      guard fm.fileExists(atPath: from) else { continue }
      guard (try? fm.moveItem(atPath: from, toPath: aside + suffix)) != nil else { continue }
      if suffix.isEmpty { kept = (aside as NSString).lastPathComponent }
    }
    return kept
  }

  // MARK: - Internals

  /// Put the target back the way it was: remove what was installed, return what was set aside.
  private static func undoInstall(at databasePath: String, restoring aside: URL?) {
    let fm = FileManager.default
    for suffix in ["", "-wal", "-shm"] { try? fm.removeItem(atPath: databasePath + suffix) }
    guard let aside else { return }
    for suffix in ["", "-wal", "-shm"] {
      let from = aside.path(percentEncoded: false) + suffix
      if fm.fileExists(atPath: from) { try? fm.moveItem(atPath: from, toPath: databasePath + suffix) }
    }
  }

  private static func stamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
    return formatter.string(from: date)
  }
}
