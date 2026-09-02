import SwiftUI

/// The ⌘, window. Auto-lock timeout is a `UserDefaults` preference; the two
/// buttons act on the open vault.
struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @AppStorage("autoLockSeconds") private var autoLockSeconds = 300

  private var unlocked: Bool { model.state == .unlocked }

  var body: some View {
    Form {
      Section("Security") {
        Picker("Auto-lock after", selection: $autoLockSeconds) {
          Text("1 minute").tag(60)
          Text("5 minutes").tag(300)
          Text("15 minutes").tag(900)
          Text("1 hour").tag(3600)
        }
        .onChange(of: autoLockSeconds) { model.autoLockSettingDidChange() }

        Button("Lock now") { model.lock() }
          .disabled(!unlocked)

        Button("Rotate recovery key…") {
          Task { await model.rotateRecoveryKey() }
        }
        .disabled(!unlocked)
      }
    }
    .formStyle(.grouped)
    .frame(width: 380)
    .padding()
  }
}
