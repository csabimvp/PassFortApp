import Foundation
import PassFortVault
import Testing

@testable import passfort_cli

/// `list`'s table and `get`'s account view: plain text for a pipe, the same text plus ANSI codes
/// at a terminal, and no secret unless asked.
@Suite struct OutputTests {

  private static let styled = Style(enabled: true)

  /// `text` without its ANSI codes.
  private static func stripped(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{1B}\\[[0-9]+m", with: "", options: .regularExpression)
  }

  private static func summary(
    _ id: String, _ title: String, username: String? = nil, host: String? = nil,
    favorite: Bool = false
  ) -> AccountSummary {
    AccountSummary(
      id: UUID(uuidString: id) ?? UUID(), title: title, username: username, host: host,
      favorite: favorite, lastUpdated: .now)
  }

  private let rows = [
    summary("A72BC9FE-96DB-4A7B-B3B1-A40BA363EFD9", "GitHub work", username: "corp"),
    summary(
      "32E68EC2-821F-4E47-BFE4-FEA4935C2FD6", "Bank of Somewhere -- online banking portal",
      host: "bank.example", favorite: true),
  ]

  // MARK: Style

  @Test func plainStyleLeavesTextAlone() {
    #expect(Style.plain.bold("x") == "x")
    #expect(Self.styled.bold("x") == "\u{1B}[1mx\u{1B}[0m")
    #expect(Self.styled.dim("") == "", "nothing to style, no codes")
  }

  @Test func truncationEndsInAnEllipsis() {
    #expect(truncated("abcdef", to: 4) == "abc…")
    #expect(truncated("abc", to: 4) == "abc")
  }

  // MARK: list

  @Test func theTableIsSortedAlignedAndCapped() {
    let table = summaryTable(rows, ids: shortIDs(rows.map(\.id)), style: .plain)
    let expected = [
      "ID        TITLE                             USERNAME  HOST",
      "32e68ec2  Bank of Somewhere -- online ban…  -         bank.example  ★",
      "a72bc9fe  GitHub work                       corp      -",
      "",
    ].joined(separator: "\n")
    #expect(table == expected)
  }

  @Test func styledTableIsThePlainOnePlusACount() {
    let ids = shortIDs(rows.map(\.id))
    let plain = summaryTable(rows, ids: ids, style: .plain)
    let styled = summaryTable(rows, ids: ids, style: Self.styled)
    #expect(styled.contains("\u{1B}["))
    #expect(Self.stripped(styled) == plain + "2 accounts\n")
  }

  @Test func anEmptyTableSaysSo() {
    #expect(summaryTable([], ids: [:], style: .plain) == "(no matching accounts)\n")
  }

  // MARK: get

  private func account(notes: String? = nil) -> Account {
    let payload = AccountPayload(
      title: "GitHub", username: "me", password: "hunter2", notes: notes, pin: "1234")
    return Account(
      id: UUID(), version: 3, updatedAt: HLC(wallMillis: 0, counter: 0, deviceID: UUID()),
      isDeleted: false, payload: payload, schemaVersion: 1, sealedSize: 0)
  }

  @Test func secretsAreHiddenUnlessRevealed() {
    let hidden = accountCard(account(), reveal: false, style: .plain)
    #expect(!hidden.contains("hunter2") && !hidden.contains("1234"))
    #expect(hidden.contains("  password  ••••••••\n"))
    #expect(hidden.contains("secrets hidden"))

    let shown = accountCard(account(), reveal: true, style: .plain)
    #expect(shown.contains("  password  hunter2\n") && shown.contains("  pin       1234\n"))
    #expect(!shown.contains("secrets hidden"))
  }

  @Test func theTitleLeadsAndMultilineValuesStayInTheirColumn() {
    let card = accountCard(account(notes: "line one\nline two"), reveal: false, style: .plain)
    #expect(card.hasPrefix("GitHub\n\n  username  me\n"))
    #expect(card.contains("  notes     line one\n            line two\n"))
  }

  @Test func fieldBlocksAlignAcrossBlocksAndSkipWhatIsEmpty() {
    let text = fieldBlocks(
      [[("a", "1"), ("skipped", nil), ("empty", "")], [("longer", "x\ny")], [("gone", nil)]],
      style: .plain)
    #expect(text == "\n  a       1\n\n  longer  x\n          y\n")
  }

  // MARK: history

  @Test func oldPasswordsAreHiddenUnlessAsked() {
    var account = account()
    account.payload.revisionHistory = [
      RevisionEntry(version: 3, at: .now, changed: ["password"]),
      RevisionEntry(version: 2, at: .now, changed: ["email", "notes"]),
    ]
    account.payload.passwordHistory = [PasswordHistoryEntry(password: "old-one", replacedAt: .now)]

    let hidden = historyView(account, passwords: false, style: .plain)
    #expect(hidden.hasPrefix("GitHub  \(account.id.uuidString), v3\n\n  v3  "))
    #expect(hidden.contains("  email, notes\n"))
    #expect(!hidden.contains("old-one") && hidden.contains("old passwords hidden"))

    let shown = historyView(account, passwords: true, style: .plain)
    #expect(shown.contains("  old-one\n") && !shown.contains("old passwords hidden"))
    #expect(Self.stripped(historyView(account, passwords: true, style: Self.styled)) == shown)
  }

  // MARK: audit

  @Test func auditListsEachFindingWithItsAccount() {
    let id = UUID()
    let findings = [
      AuditFinding(kind: .weak(score: 1), account: id),
      AuditFinding(kind: .insecureURL, account: UUID()),
    ]
    let plain = auditTable(findings, titles: [id: "GitHub"], style: .plain)
    let lines = plain.split(separator: "\n")
    #expect(lines.first == "FINDING            ACCOUNT")
    #expect(lines.dropFirst().first == "weak (score 1/4)   GitHub")
    #expect(lines.last == "2 findings")
    #expect(
      Self.stripped(auditTable(findings, titles: [id: "GitHub"], style: Self.styled)) == plain)
    #expect(auditTable([], titles: [:], style: .plain).hasPrefix("no findings"))
  }

  @Test func styledCardIsThePlainOneWithCodes() {
    let account = account()
    let plain = accountCard(account, reveal: false, style: .plain)
    let styled = accountCard(account, reveal: false, style: Self.styled)
    #expect(styled != plain && Self.stripped(styled) == plain)
  }
}
