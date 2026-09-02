import SwiftUI

@main
struct PassFortApp: App {
  @State private var model = AppModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .onChange(of: scenePhase) { _, phase in
          if phase == .background { model.lock() }
        }
    }

    Settings {
      SettingsView().environment(model)
    }
  }
}
