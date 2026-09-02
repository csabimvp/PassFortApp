import SwiftUI

/// The whole window — switches on `AppModel.state`. Each screen sizes itself;
/// `RootView` imposes no frame (stacking one around `VaultListView`'s
/// `NavigationSplitView` was triggering an AppKit layout-recursion warning).
struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    switch model.state {
    case .needsVault:
      CreateVaultView()
    case .locked, .unlocking:
      UnlockView()
    case .showingRecoveryKey(let key):
      RecoveryKeyView(key: key)
    case .unlocked:
      VaultListView()
    }
  }
}

#Preview {
  RootView().environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
