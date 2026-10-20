import AppKit

/// Moving the vault takes effect at the next launch: `AppModel`, `BackupModel` and `RestoreModel`
/// all take their database path at construction, and rebuilding them live is a bigger and riskier
/// change than one button.
@MainActor
enum AppRelauncher {
  /// Start a second instance of this app, then quit this one. If the new instance can't be started,
  /// this one keeps running so the user can quit by hand.
  static func relaunch() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) {
      _, error in
      if error == nil { DispatchQueue.main.async { NSApp.terminate(nil) } }
    }
  }

  static func quit() { NSApp.terminate(nil) }
}
