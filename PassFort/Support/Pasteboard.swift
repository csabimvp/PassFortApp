import AppKit

/// Clipboard writes for secrets (§3.2 A5: another local app reading the clipboard).
///
/// Every write carries the concealed type (`org.nspasteboard.ConcealedType`, the nspasteboard.org
/// convention), so well-behaved clipboard managers skip it instead of archiving it. `.string` is
/// set too, so pasting works everywhere.
enum Pasteboard {
  static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

  /// `UserDefaults` key for Settings ▸ General ▸ Clear copied secrets after -- a preference, not a
  /// secret.
  static let clearAfterKey = "clipboardClearSeconds"
  static let defaultClearAfter = 20

  /// How long a transient copy stays on the clipboard: the stored preference, or 20 s when none is
  /// stored (or it isn't positive).
  static func clearAfterSeconds(in defaults: UserDefaults = .standard) -> Int {
    let stored = defaults.integer(forKey: clearAfterKey)
    return stored > 0 ? stored : defaultClearAfter
  }

  /// The delay as the copy toast says it: "20 sec", "1 min".
  static var clearAfterDescription: String {
    Duration.seconds(clearAfterSeconds())
      .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
  }

  /// Each pasteboard's last transient copy that has not yet been cleared, so locking can clear it
  /// at once. The app only ever uses `.general`; keeping one per pasteboard means a copy to one
  /// can never clear another (tests copy to private pasteboards, in parallel with tests that lock).
  private static var pending: [NSPasteboard.Name: (stamp: Int, expiry: Task<Void, Never>)] = [:]

  /// Copy `string`. No auto-clear -- for a value the user is deliberately moving elsewhere (a
  /// recovery key being written down / printed). Still concealed from clipboard managers.
  static func copy(_ string: String, to board: NSPasteboard = .general) {
    _ = write(string, to: board)
  }

  /// Copy `string`, then clear it after `seconds` (the Settings preference by default) -- or
  /// sooner, via `clearTransient(on:)`, when the vault locks. Never clears something the user
  /// copied in the meantime.
  static func copyTransient(
    _ string: String, clearAfter seconds: Double = Double(clearAfterSeconds()),
    to board: NSPasteboard = .general
  ) {
    pending[board.name]?.expiry.cancel()
    let stamp = write(string, to: board)
    let expiry = Task {
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      clearTransient(on: board)
    }
    pending[board.name] = (stamp, expiry)
  }

  /// Clear `board`'s last transient copy if it is still what is on it. Called when the vault
  /// locks: a secret should not outlive the session that revealed it.
  static func clearTransient(on board: NSPasteboard = .general) {
    guard let (stamp, expiry) = pending.removeValue(forKey: board.name) else { return }
    expiry.cancel()
    if board.changeCount == stamp { board.clearContents() }
  }

  private static func write(_ string: String, to board: NSPasteboard) -> Int {
    board.clearContents()
    board.setString(string, forType: .string)
    board.setString(string, forType: concealedType)
    return board.changeCount
  }
}
