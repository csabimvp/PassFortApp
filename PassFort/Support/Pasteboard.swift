import AppKit

/// Clipboard writes for secrets (§3.2 A5: another local app reading the clipboard).
///
/// Every write carries the concealed type (`org.nspasteboard.ConcealedType`, the nspasteboard.org
/// convention), so well-behaved clipboard managers skip it instead of archiving it. `.string` is
/// set too, so pasting works everywhere.
enum Pasteboard {
  static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

  /// The last transient copy that has not yet been cleared, so locking can clear it at once.
  private static var pending: (board: NSPasteboard, stamp: Int)?
  private static var expiry: Task<Void, Never>?

  /// Copy `string`. No auto-clear -- for a value the user is deliberately moving elsewhere (a
  /// recovery key being written down / printed). Still concealed from clipboard managers.
  static func copy(_ string: String, to board: NSPasteboard = .general) {
    _ = write(string, to: board)
  }

  /// Copy `string`, then clear it after `seconds` -- or sooner, via `clearTransient()`, when the
  /// vault locks. Never clears something the user copied in the meantime.
  static func copyTransient(
    _ string: String, clearAfter seconds: Double = 20, to board: NSPasteboard = .general
  ) {
    expiry?.cancel()
    pending = (board, write(string, to: board))
    expiry = Task {
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      clearTransient()
    }
  }

  /// Clear the last transient copy if it is still what is on the clipboard. Called when the vault
  /// locks: a secret should not outlive the session that revealed it.
  static func clearTransient() {
    expiry?.cancel()
    expiry = nil
    guard let (board, stamp) = pending else { return }
    pending = nil
    if board.changeCount == stamp { board.clearContents() }
  }

  private static func write(_ string: String, to board: NSPasteboard) -> Int {
    board.clearContents()
    board.setString(string, forType: .string)
    board.setString(string, forType: concealedType)
    return board.changeCount
  }
}
