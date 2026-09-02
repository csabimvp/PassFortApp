import AppKit

/// Clipboard writes for secrets.
///
/// **M3:** plain string + a best-effort clear. **M4** replaces this with the
/// concealed pasteboard type (`org.nspasteboard.ConcealedType`, so clipboard
/// managers skip it) and a reliable expiry — the A5 mitigation, filed with the
/// other platform-integration work.
enum Pasteboard {
  /// Copy `string`. No auto-clear — for a value the user is deliberately moving
  /// elsewhere (a recovery key being written down / printed).
  static func copy(_ string: String) {
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(string, forType: .string)
  }

  /// Copy `string`, then clear it after `seconds` — unless the clipboard changed
  /// in the meantime (the user copied something else).
  static func copyTransient(_ string: String, clearAfter seconds: Double = 20) {
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(string, forType: .string)
    let stamp = board.changeCount
    Task {
      try? await Task.sleep(for: .seconds(seconds))
      if board.changeCount == stamp { board.clearContents() }
    }
  }
}
