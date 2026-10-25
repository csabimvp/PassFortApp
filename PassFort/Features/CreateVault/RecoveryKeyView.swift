import PassFortVault
import SwiftUI

/// Shows a freshly minted recovery key **once**, in the main window: first run and Start a New
/// Vault. The vault is already open (`AppModel.stagedRepo`); "I've written it down" is the gate
/// that releases it.
struct RecoveryKeyView: View {
  @Environment(AppModel.self) private var model
  let key: RecoveryKey

  var body: some View {
    RecoveryKeyPanel(key: key, title: "Recovery key") {
      Task { await model.confirmRecoveryKeyShown() }
    }
    .padding(32)
    .frame(width: 440)
  }
}

/// The recovery key and what to do with it -- shared by the main window (`RecoveryKeyView`) and
/// the Settings sheets that rotate the key or change the password. The caller decides what
/// "I've written it down" does and drops the key afterwards.
struct RecoveryKeyPanel: View {
  let key: RecoveryKey
  var title = "New recovery key"
  /// Shown under the warning when the key replaces an earlier one.
  var replacesPrevious = false
  let onDone: () -> Void

  @State private var copied = false

  var body: some View {
    VStack(spacing: 16) {
      Label(title, systemImage: "key.fill").font(.headline)

      Text(
        "Write this down and store it offline. It is shown once. It unlocks this "
          + "vault without the master password — anyone who has it can open the vault."
          + (replacesPrevious ? " The previous key no longer works." : "")
      )
      .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)

      Text(key.grouped)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

      Button(copied ? "Copied" : "Copy") {
        Pasteboard.copy(key.grouped)
        copied = true
      }
      .buttonStyle(.bordered)

      Button("I've Written It Down", action: onDone)
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
    }
  }
}

#Preview {
  RecoveryKeyView(key: .generate())
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
