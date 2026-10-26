import AppKit
import Carbon.HIToolbox
import Observation
import PassFortVault
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
  /// `UserDefaults` key for Settings ▸ General ▸ Show in menu bar (on by default).
  static let menuBarKey = "showsMenuBarExtra"
  /// Shown in Settings and the Tools menu.
  static let shortcutDescription = "⌃⌥Space"

  /// `false` when the shortcut is on but another app already owns the combination.
  private(set) var hotKeyAvailable = true

  /// The search and account last acted on, so reopening soon after picks up where you were:
  /// ⇧↩ the username, paste, ⌃⌥Space, ↩ the password -- without searching twice.
  @ObservationIgnored private var lastPick: (query: String, id: UUID, at: Date)?
  /// How long `lastPick` is offered again.
  static let reselectWindow: TimeInterval = 60

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

  /// Remember `id`, found by searching `query`, for the next open.
  func remember(query: String, id: UUID, at now: Date = .now) {
    lastPick = (query, id, now)
  }

  /// The last pick, if it is recent and still in `summaries`; otherwise nothing (and forgotten).
  func recentPick(
    in summaries: [AccountSummary], at now: Date = .now
  ) -> (query: String, id: UUID)? {
    guard let lastPick, now.timeIntervalSince(lastPick.at) < Self.reselectWindow,
      summaries.contains(where: { $0.id == lastPick.id && !$0.isDeleted })
    else {
      lastPick = nil
      return nil
    }
    return (lastPick.query, lastPick.id)
  }

  /// Bring PassFort forward with the Quick Access window on top.
  func show() {
    NSApp.activate()
    openWindow?(id: Self.windowID)
  }
}
