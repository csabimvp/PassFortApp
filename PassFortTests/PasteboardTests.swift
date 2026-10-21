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
    Pasteboard.clearTransient()

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

  @Test func clearTransientEmptiesTheClipboardImmediately() {
    let board = board()
    Pasteboard.copyTransient("secret", clearAfter: 60, to: board)
    Pasteboard.clearTransient()

    #expect(board.string(forType: .string) == nil)
  }

  @Test func clearTransientLeavesALaterCopyAlone() {
    let board = board()
    Pasteboard.copyTransient("secret", clearAfter: 60, to: board)
    board.clearContents()
    board.setString("something else", forType: .string)
    Pasteboard.clearTransient()

    #expect(board.string(forType: .string) == "something else")
  }
}
