import SwiftUI

/// Settings ▸ General: preferences only, all `UserDefaults`, none of them secret. They apply
/// whether the vault is open or not.
struct SettingsView: View {
  @Environment(AppModel.self) private var model
  /// Optional so previews that only inject `AppModel` keep working.
  @Environment(QuickAccessController.self) private var quickAccess: QuickAccessController?
  @AppStorage(QuickAccessController.enabledKey) private var quickAccessEnabled = true
  @AppStorage(QuickAccessController.menuBarKey) private var showsMenuBarExtra = true
  @AppStorage("autoLockSeconds") private var autoLockSeconds = 300
  @AppStorage(Pasteboard.clearAfterKey) private var clearAfterSeconds = Pasteboard.defaultClearAfter

  var body: some View {
    Form {
      Section {
        Picker("Lock after inactivity", selection: $autoLockSeconds) {
          Text("1 minute").tag(60)
          Text("5 minutes").tag(300)
          Text("15 minutes").tag(900)
          Text("1 hour").tag(3600)
        }
        .onChange(of: autoLockSeconds) { model.autoLockSettingDidChange() }
      } header: {
        Text("Locking")
      } footer: {
        SettingsFooter("PassFort also locks at once when the Mac sleeps or the screen locks.")
      }

      Section {
        Picker("Clear copied secrets after", selection: $clearAfterSeconds) {
          Text("10 seconds").tag(10)
          Text("20 seconds").tag(20)
          Text("30 seconds").tag(30)
          Text("1 minute").tag(60)
          Text("2 minutes").tag(120)
        }
      } header: {
        Text("Clipboard")
      } footer: {
        SettingsFooter("Copies are hidden from clipboard managers, and cleared when the vault locks.")
      }

      Section("Quick Access") {
        Toggle(
          "Keyboard shortcut (\(QuickAccessController.shortcutDescription))",
          isOn: $quickAccessEnabled
        )
        .onChange(of: quickAccessEnabled) { quickAccess?.applySetting() }
        if quickAccessEnabled, quickAccess?.hotKeyAvailable == false {
          let elsewhere = showsMenuBarExtra ? "the menu bar and the Tools menu" : "the Tools menu"
          Text(
            "Another app is using \(QuickAccessController.shortcutDescription). Quick Access is "
              + "still in \(elsewhere).")
            .font(.caption).foregroundStyle(Palette.warning)
            .fixedSize(horizontal: false, vertical: true)
        }
        Toggle("Show in menu bar", isOn: $showsMenuBarExtra)
      }
    }
    .settingsTab()
  }
}

/// A section footer in Settings: small, secondary, wrapping.
struct SettingsFooter: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text).font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}

extension View {
  /// Every Settings tab: a grouped form at one width, so switching tabs doesn't resize the window.
  func settingsTab() -> some View {
    formStyle(.grouped).frame(width: 500)
  }
}
