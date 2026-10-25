import SwiftUI

/// Settings ▸ Security: the two changes to how the vault is unlocked. Both need it open, and both
/// show any new recovery key on this window (`RecoveryKeyPanel`).
struct SecuritySettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var changingPassword = false

  private var unlocked: Bool { model.state == .unlocked }

  var body: some View {
    Form {
      if !unlocked {
        LockedSettingsNotice(message: "Unlock it to change the master password or recovery key.")
      }

      Group {
        Section {
          LabeledContent("Master password") {
            Button("Change…") { changingPassword = true }
          }
        } header: {
          Text("Master password")
        } footer: {
          SettingsFooter(
            "Needs the current password. Backups made before the change still open with the old "
              + "one.")
        }

        Section {
          LabeledContent("Recovery key") { RotateRecoveryKeyButton() }
        } header: {
          Text("Recovery key")
        } footer: {
          SettingsFooter(
            "Opens the vault if the master password is forgotten. Rotating replaces it, or adds "
              + "one if the vault has none; the current key stops working.")
        }
      }
      .disabled(!unlocked)
      .opacity(unlocked ? 1 : 0.45)
    }
    .settingsTab()
    .sheet(isPresented: $changingPassword) {
      ChangePasswordView().environment(model)
    }
  }
}
