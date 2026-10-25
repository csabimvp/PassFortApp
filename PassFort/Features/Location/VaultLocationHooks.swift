import Foundation

extension VaultLocationModel.Hooks {
  /// The app's side of a move: a mid-run backup refuses it, backups pause while the files move
  /// (and stay paused after a successful move, since this process still points at the old place),
  /// and an open vault is locked first.
  @MainActor
  static func app(_ model: AppModel, _ backup: BackupModel?) -> Self {
    Self(
      begin: {
        if backup?.isRunning == true { return "A backup is running. Try again in a moment." }
        backup?.setPaused(true)
        return nil
      },
      releaseVault: { if model.state != .needsVault { await model.lockAndRelease() } },
      abandon: { backup?.setPaused(false) })
  }
}

extension AppModel.State {
  /// Not while a vault is being created or unlocked: its files are in use.
  var allowsFileMoves: Bool {
    switch self {
    case .unlocking, .showingRecoveryKey: return false
    case .needsVault, .locked, .unlocked: return true
    }
  }
}
