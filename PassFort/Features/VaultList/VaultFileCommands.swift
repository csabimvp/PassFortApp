import SwiftUI

/// The File menu's vault items: the operations that put another vault in this one's place, Restore
/// from Backup, and Lock. They used to sit in Settings; as commands they read like a document app's
/// New / Open, and Lock's ⌘L shows in a menu. Each sheet opens on the vault window, brought forward
/// first so it doesn't open behind Settings.
struct VaultFileCommands: Commands {
  let model: AppModel
  let location: VaultLocationModel

  @Environment(\.openWindow) private var openWindow

  /// The swaps need the vault open, and the files free to move. Settings ▸ Vault's New Vault…
  /// asks the same.
  static func canReplace(_ model: AppModel, _ location: VaultLocationModel) -> Bool {
    model.state == .unlocked && !location.isBusy && !location.needsRelaunch
  }

  private var canReplace: Bool { Self.canReplace(model, location) }

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
    Self.show(sheet, model, openWindow)
  }

  /// Open one of the sheets on the vault window, brought forward first -- from the menu, or from
  /// Settings. Never on the Settings window: a new vault's recovery key appears in the vault
  /// window, which must not be left behind Settings.
  static func show(_ sheet: AppModel.VaultSheet, _ model: AppModel, _ openWindow: OpenWindowAction) {
    MainWindow.bringForward(openWindow)
    model.vaultSheet = sheet
  }
}
