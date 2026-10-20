import SwiftUI

@main
struct PassFortApp: App {
  @State private var model = AppModel()
  @State private var backup = BackupModel()
  @State private var showingGenerator = false
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .environment(backup)
        .tint(Palette.primary)
        .onChange(of: model.state) { old, new in
          // Only a real lock counts -- not a failed unlock attempt (.unlocking -> .locked).
          if old == .unlocked, case .locked = new { Task { await backup.vaultDidLock() } }
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
        BackupSettingsView().environment(model).environment(backup).tint(Palette.primary)
          .tabItem { Label("Backup", systemImage: "externaldrive") }
      }
    }
  }
}
