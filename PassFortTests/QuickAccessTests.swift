import AppKit
import Foundation
import PassFortCrypto
import PassFortVault
import Testing

@testable import PassFort

/// Quick Access: the result ranking, and `AppModel.copy` — against a throwaway named pasteboard,
/// never the user's real clipboard.
@MainActor
@Suite(.serialized)
struct QuickAccessTests {

  private func summary(
    _ title: String, username: String? = nil, host: String? = nil, tags: [String] = [],
    favorite: Bool = false, deleted: Bool = false
  ) -> AccountSummary {
    AccountSummary(
      id: UUID(), title: title, username: username, host: host, tags: tags, favorite: favorite,
      isDeleted: deleted, lastUpdated: Date())
  }

  // MARK: - Ranking

  @Test func titlePrefixBeatsContainsBeatsUsernameBeatsTag() {
    let rows = [
      summary("Work tools", tags: ["git"]),
      summary("Bank", username: "gitfan"),
      summary("My GitLab"),
      summary("GitHub"),
    ]
    #expect(
      quickMatches(from: rows, query: "git").map(\.title)
        == ["GitHub", "My GitLab", "Bank", "Work tools"])
  }

  @Test func favoritesComeFirstWithinATier() {
    let rows = [summary("Gmail"), summary("GitHub", favorite: true)]
    #expect(quickMatches(from: rows, query: "g").map(\.title) == ["GitHub", "Gmail"])
  }

  @Test func deletedAccountsNeverMatchAndTheLimitHolds() {
    var rows = [summary("Gone", deleted: true)]
    rows += (0..<20).map { summary("Account \($0)") }
    let matches = quickMatches(from: rows, query: "", limit: 8)
    #expect(matches.count == 8)
    #expect(!matches.contains { $0.title == "Gone" })
  }

  @Test func noMatchIsEmpty() {
    #expect(quickMatches(from: [summary("GitHub")], query: "zzz").isEmpty)
  }

  // MARK: - Copy

  @Test func copyPutsTheChosenFieldOnTheBoardAndReportsAMissingOne() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-qa-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    _ = try await Vault.create(
      databasePath: path, password: Data("pw".utf8),
      params: KdfParameters(
        kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16)),
      deviceID: VaultService.deviceID)

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    _ = await model.createAccount(
      AccountPayload(
        title: "GitHub", username: "me", password: "hunter2",
        totp: TOTPConfig(secret: Data("12345678901234567890".utf8))))
    _ = await model.createAccount(AccountPayload(title: "Note"))
    let github = try #require(model.summaries.first { $0.title == "GitHub" }).id
    let note = try #require(model.summaries.first { $0.title == "Note" }).id

    let board = NSPasteboard(name: NSPasteboard.Name("app.passfort.tests.\(UUID().uuidString)"))
    #expect(await model.copy(.password, from: github, to: board) == nil)
    #expect(board.string(forType: .string) == "hunter2")
    #expect(board.string(forType: Pasteboard.concealedType) == "hunter2")
    #expect(await model.copy(.username, from: github, to: board) == nil)
    #expect(board.string(forType: .string) == "me")
    #expect(await model.copy(.oneTimeCode, from: github, to: board) == nil)
    #expect(board.string(forType: .string)?.count == 6)

    #expect(await model.copy(.password, from: note, to: board) != nil)
    #expect(board.string(forType: .string)?.count == 6)  // a failed copy leaves the board alone

    model.lock()  // locking clears the transient copy
    #expect(board.string(forType: .string) == nil)
  }
}
