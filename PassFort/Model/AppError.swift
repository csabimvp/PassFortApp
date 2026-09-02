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
  /// Anything else — I/O, an unexpected status.
  case io(String)

  /// True for `.rolledBack` — the one failure the user can clear themselves
  /// (the GUI's `verify --accept-restore`).
  var isRestorableRollback: Bool {
    if case .rolledBack = self { return true }
    return false
  }
}
