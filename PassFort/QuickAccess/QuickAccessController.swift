import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// Owns the ⌃⌥Space shortcut and knows how to open the Quick Access window.
///
/// SwiftUI only hands out `openWindow` inside a view, so the first view that appears passes it in
/// (`adopt(_:)`); the hot key then calls it from outside the view hierarchy.
@MainActor @Observable
final class QuickAccessController {
  static let windowID = "quick-access"
  /// `UserDefaults` key for the Settings toggle — a preference, not a secret.
  static let enabledKey = "quickAccessHotKeyEnabled"
  /// Shown in Settings and the Tools menu.
  static let shortcutDescription = "⌃⌥Space"

  /// `false` when the shortcut is on but another app already owns the combination.
  private(set) var hotKeyAvailable = true

  @ObservationIgnored private var openWindow: OpenWindowAction?
  @ObservationIgnored private var hotKey: GlobalHotKey?

  /// Called by the first view to appear with an `openWindow` in its environment.
  func adopt(_ action: OpenWindowAction) {
    guard openWindow == nil else { return }
    openWindow = action
    applySetting()
  }

  /// Register or drop the shortcut to match the Settings toggle (on by default).
  func applySetting() {
    let enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    if enabled, hotKey == nil {
      hotKey = GlobalHotKey(keyCode: kVK_Space, modifiers: controlKey | optionKey) { [weak self] in
        self?.show()
      }
      hotKeyAvailable = hotKey != nil
    } else if !enabled {
      hotKey = nil
      hotKeyAvailable = true
    }
  }

  /// Bring PassFort forward with the Quick Access window on top.
  func show() {
    NSApp.activate()
    openWindow?(id: Self.windowID)
  }
}
