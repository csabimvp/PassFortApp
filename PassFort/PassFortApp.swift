import SwiftUI

@main
struct PassFortApp: App {
  @State private var location: VaultLocationModel
  @State private var model: AppModel
  @State private var backup: BackupModel
  @State private var showingGenerator = false
  @Environment(\.scenePhase) private var scenePhase

  init() {
    // Decided once, before anything opens the vault. The models below all take this path.
    let location = VaultLocationModel.launch()
    _location = State(initialValue: location)
    _model = State(
      initialValue: AppModel(
        databasePath: location.databasePath, highWaterURL: location.highWaterURL))
    _backup = State(initialValue: BackupModel(databasePath: location.databasePath))
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if location.needsRelaunch {
          RelaunchRequiredView()
        } else if !location.isUsable {
          VaultLocationUnavailableView()
        } else {
          RootView()
        }
      }
        .environment(model)
        .environment(backup)
        .environment(location)
        .tint(Palette.primary)
        .onChange(of: model.state) { old, new in
          if BackupModel.isLock(from: old, to: new) { Task { await backup.vaultDidLock() } }
        }
        .onChange(of: scenePhase) { _, phase in
          if phase == .background { model.lock() }
        }
        .sheet(isPresented: $showingGenerator) {
          PasswordGeneratorView().tint(Palette.primary)
        }
    }
    .defaultSize(width: 860, height: 540)
    .commands {
      CommandMenu("Tools") {
        Button("Generate Password…") { showingGenerator = true }
          .keyboardShortcut("g", modifiers: [.command, .option])
      }
    }

    Settings {
      TabView {
        SettingsView().environment(model).tint(Palette.primary)
          .tabItem { Label("General", systemImage: "gearshape") }
        VaultLocationSettingsView().environment(model).environment(location).environment(backup)
          .tint(Palette.primary)
          .tabItem { Label("Vault", systemImage: "lock.doc") }
        BackupSettingsView().environment(model).environment(backup).environment(location)
          .tint(Palette.primary)
          .tabItem { Label("Backup", systemImage: "externaldrive") }
      }
    }
  }
}
