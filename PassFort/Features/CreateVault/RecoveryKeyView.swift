import PassFortVault
import SwiftUI

/// Shows a freshly minted recovery key **once**. The vault is already open
/// (`AppModel.stagedRepo`); "I've written it down" is the gate that releases it.
struct RecoveryKeyView: View {
  @Environment(AppModel.self) private var model
  let key: RecoveryKey

  @State private var copied = false

  var body: some View {
    VStack(spacing: 16) {
      Label("Recovery key", systemImage: "key.fill").font(.headline)

      Text(
        "Write this down and store it offline. It is shown once. It unlocks this "
          + "vault without the master password — anyone who has it can open the vault."
      )
      .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

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

      Button("I've written it down — continue") {
        Task { await model.confirmRecoveryKeyShown() }
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
    }
    .padding(32)
    .frame(width: 440)
  }
}

#Preview {
  RecoveryKeyView(key: .generate())
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
