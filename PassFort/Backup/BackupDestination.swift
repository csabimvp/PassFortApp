import Foundation

/// Somewhere finished backup files can be put: today a folder (the NAS share), later an Azure
/// Blob container (`docs/runbooks/m3-vault-management.md` Phase 6).
///
/// A destination only moves files that `VaultBackup.create` already produced; it knows nothing
/// about vaults, keys or SQLite. Every method does blocking file I/O, possibly over a network
/// share, so each is `@concurrent` -- it must never run on the main actor.
nonisolated protocol BackupDestination: Sendable {
  /// Whether a place to put backups has been chosen. Says nothing about whether it is reachable.
  var isConfigured: Bool { get }

  /// A short name for the status line, e.g. "PassFort" for `/Volumes/nas/Zeus/PassFort`.
  var displayName: String { get }

  /// Where a person would look for the files, for opening a file picker there. A hint only: it
  /// grants no access. `nil` when the destination isn't a folder.
  var folderURL: URL? { get }

  /// Copy the local backup `file` into the destination under its own file name, atomically (a
  /// half-copied file is never visible under the final name), and confirm it landed intact.
  /// Never overwrites. Returns the stored file's name.
  @concurrent func store(_ file: URL) async throws -> String

  /// Names of this vault's backups at the destination, newest first.
  @concurrent func list(vaultID: UUID) async throws -> [String]

  /// Delete all but the newest `keep` of this vault's backups. Returns the names removed.
  @concurrent func prune(vaultID: UUID, keep: Int) async throws -> [String]
}
