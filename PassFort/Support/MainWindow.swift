import AppKit
import SwiftUI

/// The vault window (the `WindowGroup` with `PassFortApp.mainWindowID`), for the places outside it
/// that act on it: Settings' Unlock…, and the File menu's sheets, which it presents.
@MainActor
enum MainWindow {
  /// Bring PassFort and the vault window forward -- the one that's open, or a new one.
  static func bringForward(_ openWindow: OpenWindowAction) {
    NSApp.activate()
    let window = NSApp.windows.first {
      $0.identifier?.rawValue.hasPrefix(PassFortApp.mainWindowID) == true
    }
    if let window {
      window.makeKeyAndOrderFront(nil)
    } else {
      openWindow(id: PassFortApp.mainWindowID)
    }
  }
}
