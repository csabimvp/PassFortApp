import AppKit
import Testing

@testable import PassFort

/// Against throwaway named pasteboards, never the user's real clipboard. Serialized because
/// `Pasteboard` tracks one pending transient copy in static state, as the app does.
@MainActor
@Suite(.serialized)
struct PasteboardTests {

  private func board() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("app.passfort.tests.\(UUID().uuidString)"))
  }

  @Test func copiesCarryTheConcealedTypeAndPlainString() {
    let board = board()
    Pasteboard.copy("hunter2", to: board)

    #expect(board.string(forType: .string) == "hunter2")
    #expect(board.string(forType: Pasteboard.concealedType) == "hunter2")
  }

  @Test func aPlainCopyIsNotAutoCleared() {
    let board = board()
    Pasteboard.copy("recovery key", to: board)
    Pasteboard.clearTransient(on: board)

    #expect(board.string(forType: .string) == "recovery key")
  }

  @Test func aTransientCopyClearsAfterTheDelay() async throws {
    let board = board()
    Pasteboard.copyTransient("secret", clearAfter: 0.05, to: board)
    #expect(board.string(forType: .string) == "secret")

    try await Task.sleep(for: .milliseconds(300))
    #expect(board.string(forType: .string) == nil)
  }

  @Test func theTimedClearLeavesALaterCopyAlone() async throws {
    let board = board()
    Pasteboard.copyTransient("secret", clearAfter: 0.05, to: board)
    board.clearContents()
    board.setString("something else", forType: .string)

    try await Task.sleep(for: .milliseconds(300))
    #expect(board.string(forType: .string) == "something else")
  }

  @Test func theDefaultDelayFollowsThePreference() throws {
    let defaults = try #require(UserDefaults(suiteName: "app.passfort.tests.\(UUID().uuidString)"))
    #expect(Pasteboard.clearAfterSeconds(in: defaults) == 20)

    defaults.set(90, forKey: Pasteboard.clearAfterKey)
    #expect(Pasteboard.clearAfterSeconds(in: defaults) == 90)

    defaults.set(0, forKey: Pasteboard.clearAfterKey)
    #expect(Pasteboard.clearAfterSeconds(in: defaults) == 20)
  }

  @Test func clearTransientEmptiesTheClipboardImmediately() {
    let board = board()
    Pasteboard.copyTransient("secret", clearAfter: 60, to: board)
    Pasteboard.clearTransient(on: board)

    #expect(board.string(forType: .string) == nil)
  }

  @Test func clearTransientLeavesALaterCopyAlone() {
    let board = board()
    Pasteboard.copyTransient("secret", clearAfter: 60, to: board)
    board.clearContents()
    board.setString("something else", forType: .string)
    Pasteboard.clearTransient(on: board)

    #expect(board.string(forType: .string) == "something else")
  }

  /// The flake this fixes: a lock elsewhere (any test's `AppModel.lock()` clears `.general`) used
  /// to clear the one pending copy wherever it was, including another test's private board.
  @Test func clearingOneBoardLeavesAnotherBoardsCopy() {
    let mine = board()
    let other = board()
    Pasteboard.copyTransient("mine", clearAfter: 60, to: mine)
    Pasteboard.copyTransient("other", clearAfter: 60, to: other)

    Pasteboard.clearTransient(on: other)
    Pasteboard.clearTransient()  // .general, as a lock does
    #expect(mine.string(forType: .string) == "mine")
    #expect(other.string(forType: .string) == nil)

    Pasteboard.clearTransient(on: mine)
    #expect(mine.string(forType: .string) == nil)
  }
}
