import AppKit
import SwiftUI

/// The one way a Settings tab says it needs the vault open: this row at the top, with the tab's
/// controls dimmed beneath it. **Unlock…** brings the main window, where the Unlock screen is,
/// forward. Tabs that work while locked (Vault, Backup) don't show it.
struct LockedSettingsNotice: View {
  /// What unlocking lets you do here, e.g. "Unlock it to change the master password."
  let message: String

  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Section {
      HStack(spacing: 12) {
        Image(systemName: "lock.fill")
          .foregroundStyle(Palette.primary)
          .frame(width: 30, height: 30)
          .background(Palette.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        VStack(alignment: .leading, spacing: 2) {
          Text("PassFort is locked").fontWeight(.semibold)
          Text(message).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Button("Unlock…", action: showMainWindow)
      }
    }
  }

  /// The vault window if one is open, a new one if not.
  private func showMainWindow() {
    NSApp.activate()
    let main = NSApp.windows.first {
      $0.identifier?.rawValue.hasPrefix(PassFortApp.mainWindowID) == true
    }
    if let main {
      main.makeKeyAndOrderFront(nil)
    } else {
      openWindow(id: PassFortApp.mainWindowID)
    }
  }
}
