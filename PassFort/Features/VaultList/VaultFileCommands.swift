import SwiftUI

/// The File menu's vault items: the operations that put another vault in this one's place, Restore
/// from Backup, and Lock. They used to sit in Settings; as commands they read like a document app's
/// New / Open, and Lock's ⌘L shows in a menu. Each sheet opens on the vault window, brought forward
/// first so it doesn't open behind Settings.
struct VaultFileCommands: Commands {
  let model: AppModel
  let location: VaultLocationModel

  @Environment(\.openWindow) private var openWindow

  /// The swaps need the vault open, and the files free to move.
  private var canReplace: Bool {
    model.state == .unlocked && !location.isBusy && !location.needsRelaunch
  }

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Divider()
      Button("New Vault…") { show(.newVault) }
        .disabled(!canReplace)
      Button("Open Vault…") { show(.openVault) }
        .disabled(!canReplace)
      Button("Join Synced Vault…") { show(.joinVault) }
        .disabled(!canReplace || !model.syncAvailable)
      Divider()
      Button("Restore from Backup…") {
        MainWindow.bringForward(openWindow)
        model.showingRestore = true
      }
      .disabled(!RestoreBackupFlow.isAllowed(model, location))
      Divider()
      Button("Lock") { model.lock() }
        .keyboardShortcut("l", modifiers: .command)
        .disabled(model.state != .unlocked)
    }
  }

  private func show(_ sheet: AppModel.VaultSheet) {
    MainWindow.bringForward(openWindow)
    model.vaultSheet = sheet
  }
}
