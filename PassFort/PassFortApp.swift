import SwiftUI

@main
struct PassFortApp: App {
  @State private var model = AppModel()
  @State private var showingGenerator = false
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .onChange(of: scenePhase) { _, phase in
          if phase == .background { model.lock() }
        }
        .sheet(isPresented: $showingGenerator) {
          PasswordGeneratorView()
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
      SettingsView().environment(model)
    }
  }
}
