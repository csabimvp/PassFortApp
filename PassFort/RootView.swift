import SwiftUI

/// Switches on `AppModel.state`. Phases 3–5 replace each placeholder with the
/// real screen (Unlock / CreateVault / VaultList).
struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Group {
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
    .frame(minWidth: 360, minHeight: 260)
  }

  private func placeholder(_ title: String, _ subtitle: String) -> some View {
    VStack(spacing: 8) {
      Image(systemName: "lock.rectangle").font(.largeTitle).foregroundStyle(.secondary)
      Text(title).font(.headline)
      Text(subtitle).font(.caption).foregroundStyle(.secondary)
    }
    .padding(40)
  }
}

#Preview {
  RootView().environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
