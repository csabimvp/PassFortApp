import PassFortVault
import SwiftUI

/// The ⌘, window. Auto-lock timeout is a `UserDefaults` preference; the
/// buttons act on the open vault.
struct SettingsView: View {
  @Environment(AppModel.self) private var model
  /// Optional so previews that only inject `AppModel` keep working.
  @Environment(QuickAccessController.self) private var quickAccess: QuickAccessController?
  @AppStorage(QuickAccessController.enabledKey) private var quickAccessEnabled = true
  @AppStorage("autoLockSeconds") private var autoLockSeconds = 300
  @State private var cryptoStats: VaultRepository.CryptoStats?
  @State private var changingPassword = false

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

        Toggle(
          "Quick Access shortcut (\(QuickAccessController.shortcutDescription))",
          isOn: $quickAccessEnabled
        )
        .onChange(of: quickAccessEnabled) { quickAccess?.applySetting() }
        if quickAccessEnabled, quickAccess?.hotKeyAvailable == false {
          Text("Another app is using this shortcut.").font(.caption).foregroundStyle(Palette.warning)
        }

        Button("Lock now") { model.lock() }
          .disabled(!unlocked)

        Button("Change master password…") { changingPassword = true }
          .disabled(!unlocked)

        LabeledContent("Recovery key") { RotateRecoveryKeyButton() }
      }

      if unlocked {
        Section("Crypto activity") {
          LabeledContent("Records sealed", value: "\(cryptoStats?.sealCount ?? 0)")
          LabeledContent("Records opened", value: "\(cryptoStats?.openCount ?? 0)")
          Button("Refresh") { Task { await refreshCryptoStats() } }
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 380)
    .padding()
    .task(id: unlocked) { await refreshCryptoStats() }
    .sheet(isPresented: $changingPassword) {
      ChangePasswordView().environment(model)
    }
  }

  private func refreshCryptoStats() async {
    cryptoStats = await model.cryptoStats()
  }
}
