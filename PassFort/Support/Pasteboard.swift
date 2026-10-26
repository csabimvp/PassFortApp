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
  /// Each pasteboard's paste sequence still in progress. Held here because a pasteboard item
  /// doesn't retain its data provider.
  private static var sequences: [NSPasteboard.Name: PasteSequence] = [:]

  /// How long a pasted value stays before the next one replaces it: an app that reads the
  /// clipboard twice for one paste still gets the same value, and nobody moves to the next field
  /// this fast. The provider can't hand over the value and replace it in the same breath -- a
  /// replacement that soon reaches the pasting app as an empty clipboard.
  static let advanceDelay: Duration = .milliseconds(250)

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
    sequences[board.name] = nil
    scheduleClear(on: board, stamp: write(string, to: board), after: seconds)
  }

  /// Put `values` on the clipboard one paste at a time: the first paste gets `values[0]`, the next
  /// paste `values[1]`, and after the last one the clipboard clears -- username, then password,
  /// without going back to PassFort in between. Each value is only *promised* (an
  /// `NSPasteboardItemDataProvider`) and handed over when an app pastes it, so the password isn't
  /// on the clipboard until it's pasted. An app that only checks what types are there (to enable
  /// its Paste menu item) doesn't advance it. Concealed, and cleared like `copyTransient`: each
  /// step after `seconds` unpasted, or on lock.
  ///
  /// - Parameter pasted: Called after each paste with how many values are left (0 when done).
  static func copySequence(
    _ values: [String], clearAfter seconds: Double = Double(clearAfterSeconds()),
    to board: NSPasteboard = .general, pasted: @escaping (_ left: Int) -> Void = { _ in }
  ) {
    guard !values.isEmpty else { return }
    let sequence = PasteSequence(values: values, pasted: pasted)
    sequences[board.name] = sequence
    promiseNext(of: sequence, on: board, clearAfter: seconds)
  }

  /// Clear `board`'s last transient copy if it is still what is on it. Called when the vault
  /// locks: a secret should not outlive the session that revealed it.
  static func clearTransient(on board: NSPasteboard = .general) {
    sequences[board.name] = nil
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

  /// Clear `board` after `seconds` unless something else is on it by then.
  private static func scheduleClear(on board: NSPasteboard, stamp: Int, after seconds: Double) {
    pending[board.name]?.expiry.cancel()
    let expiry = Task {
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      clearTransient(on: board)
    }
    pending[board.name] = (stamp, expiry)
  }

  /// Promise `sequence`'s next value on `board`. The concealed marker is written as an empty
  /// string -- the convention only needs the type present, and its value would be an eager copy.
  private static func promiseNext(
    of sequence: PasteSequence, on board: NSPasteboard, clearAfter seconds: Double
  ) {
    let item = NSPasteboardItem()
    item.setString("", forType: concealedType)
    item.setDataProvider(sequence, forTypes: [.string])
    board.clearContents()
    board.writeObjects([item])
    scheduleClear(on: board, stamp: board.changeCount, after: seconds)
    sequence.provided = {
      Task {
        try? await Task.sleep(for: advanceDelay)
        // Cleared, locked, replaced by another copy, or the user copied something meanwhile.
        guard sequences[board.name] === sequence, pending[board.name]?.stamp == board.changeCount
        else { return }
        sequence.values.removeFirst()
        sequence.pasted(sequence.values.count)
        if sequence.values.isEmpty {
          clearTransient(on: board)
        } else {
          promiseNext(of: sequence, on: board, clearAfter: seconds)
        }
      }
    }
  }
}

/// The data provider behind `Pasteboard.copySequence`: hands over the first of `values` when an
/// app pastes, and tells `Pasteboard` once per promise so it can move to the next.
private final class PasteSequence: NSObject, NSPasteboardItemDataProvider {
  var values: [String]
  let pasted: (_ left: Int) -> Void
  /// Set by each promise, consumed by its first paste: the pasteboard caches what we hand over,
  /// but a repeat call must not advance twice.
  var provided: (() -> Void)?

  init(values: [String], pasted: @escaping (_ left: Int) -> Void) {
    self.values = values
    self.pasted = pasted
  }

  // AppKit calls both on the main thread, for in-process and cross-process pastes alike.
  nonisolated func pasteboard(
    _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
    provideDataForType type: NSPasteboard.PasteboardType
  ) {
    MainActor.assumeIsolated {
      guard let value = values.first else { return }
      item.setString(value, forType: type)
      provided?()
      provided = nil
    }
  }

  nonisolated func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}
