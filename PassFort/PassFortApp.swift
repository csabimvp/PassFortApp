import SwiftUI

@main
struct PassFortApp: App {
  @State private var location: VaultLocationModel
  @State private var model: AppModel
  @State private var backup: BackupModel
  @State private var quickAccess = QuickAccessController()
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
        .sheet(isPresented: $model.showingGenerator) {
          PasswordGeneratorView().tint(Palette.primary)
        }
        .modifier(AdoptOpenWindow(controller: quickAccess))
    }
    .defaultSize(width: 1240, height: 720)
    .commands {
      AccountCommands()
      CommandMenu("Tools") {
        Button("Generate Password…") { model.showingGenerator = true }
          .keyboardShortcut("g", modifiers: [.command, .option])
        Button("Quick Access (\(QuickAccessController.shortcutDescription))") { quickAccess.show() }
        Divider()
        Button("Import from Password Safe…") { model.showingImport = true }
          .disabled(model.state != .unlocked)
      }
    }

    Window("Quick Access", id: QuickAccessController.windowID) {
      QuickAccessView()
        .environment(model)
        .tint(Palette.primary)
    }
    .windowResizability(.contentSize)
    .windowStyle(.hiddenTitleBar)
    .defaultPosition(.center)

    MenuBarExtra("PassFort", systemImage: "key.fill") {
      QuickAccessView()
        .environment(model)
        .tint(Palette.primary)
        .modifier(AdoptOpenWindow(controller: quickAccess))
    }
    .menuBarExtraStyle(.window)

    Settings {
      TabView {
        SettingsView().environment(model).environment(quickAccess).tint(Palette.primary)
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

/// Hands the environment's `openWindow` to the Quick Access controller, so the global shortcut can
/// open its window from outside any view.
private struct AdoptOpenWindow: ViewModifier {
  @Environment(\.openWindow) private var openWindow
  let controller: QuickAccessController

  func body(content: Content) -> some View {
    content.onAppear { controller.adopt(openWindow) }
  }
}
