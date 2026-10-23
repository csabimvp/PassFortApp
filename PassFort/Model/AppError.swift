/// User-facing failures from the vault layer — the GUI counterpart of the CLI's
/// error translation in `VaultCLI.open`. `VaultService.map` turns `PassFortError`
/// / `VaultError` / `VaultManifest.Failure` into one of these.
enum AppError: Error, Equatable {
  /// Wrong master password, or a corrupt header (`PassFortError.authFailed`) —
  /// deliberately indistinguishable from a plain wrong password (§13.1).
  case wrongPassword
  /// The file exists but holds no vault (`VaultError.notFound`).
  case notAVault
  /// The manifest MAC doesn't match — a record was changed outside PassFort
  /// (`VaultManifest.Failure.macMismatch`). Not safe to open.
  case tampered
  /// The file is behind the anti-rollback mark (`.rollbackDetected`): a restored
  /// backup or a rolled-back file. The versions drive the Unlock screen's
  /// "this was a backup I restored" prompt (Phase 3).
  case rolledBack(fileVersion: UInt64, lastSeen: UInt64)
  /// A folder can't hold the live vault (network drive, synced folder, not writable...). The value
  /// is the full sentence to show.
  case locationNotAllowed(String)
  /// A file picked for restore isn't a usable PassFort vault backup.
  case notABackup
  /// Backups have no destination folder yet (Settings ▸ Backup ▸ Choose Folder).
  case backupNotConfigured
  /// The destination folder can't be reached — typically the NAS isn't mounted, or the folder was
  /// deleted. The associated value is the folder's name, for the message.
  case backupDestinationUnavailable(String)
  /// Another vault picked to import from can't be used (`VaultImport.Failure`, or a recovery key
  /// for a vault without one). The value is the full sentence to show.
  case importRefused(String)
  /// A vault picked to load can't be used (not a vault, or a copy of the open one). The value is
  /// the full sentence to show.
  case loadRefused(String)
  /// Something else is using the vault's files right now (a backup mid-run). The value is the full
  /// sentence to show.
  case notNow(String)
  /// Anything else — I/O, an unexpected status.
  case io(String)

  /// True for `.rolledBack` — the one failure the user can clear themselves
  /// (the GUI's `verify --accept-restore`).
  var isRestorableRollback: Bool {
    if case .rolledBack = self { return true }
    return false
  }

  /// A plain sentence for a banner. `UnlockView`'s `.rolledBack` branch builds its
  /// own richer layout; everything else can use this.
  var message: String {
    switch self {
    case .wrongPassword:
      return "Wrong password."
    case .notAVault:
      return "There's no vault at that location."
    case .tampered:
      return "This vault was modified outside PassFort and isn't safe to open."
    case .rolledBack(let fileVersion, let lastSeen):
      return "This vault is v\(fileVersion); this Mac last saw v\(lastSeen). It looks rolled back."
    case .locationNotAllowed(let reason), .importRefused(let reason), .loadRefused(let reason),
      .notNow(let reason):
      return reason
    case .notABackup:
      return "That file isn't a PassFort vault backup."
    case .backupNotConfigured:
      return "Choose a backup folder first."
    case .backupDestinationUnavailable(let folder):
      return "The backup folder “\(folder)” isn't available. Is the NAS connected?"
    case .io(let detail):
      return "Something went wrong: \(detail)"
    }
  }
}
