import Foundation
import PassFortCrypto
import Testing

@testable import PassFortVault

/// Password Safe text-export import, against `Fixtures/import/passwordsafe-export.txt`: the
/// header of a real Password Safe 3.x export, with made-up rows.
@Suite struct PasswordSafeImportTests {

  private static let fixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Fixtures/import/passwordsafe-export.txt")

  private let utc = TimeZone(identifier: "UTC") ?? .current

  private func plan() throws -> ImportPlan {
    try PasswordSafeImport.plan(try Data(contentsOf: Self.fixture), timeZone: utc)
  }

  private func account(_ title: String, in plan: ImportPlan) throws -> AccountPayload {
    try #require(plan.accounts.first { $0.payload.title == title }).payload
  }

  private func utcDate(_ text: String) throws -> Date {
    try #require(PasswordSafeImport.date(text, timeZone: utc))
  }

  // MARK: - The fixture

  @Test func readsEveryRowWithATitleAndSkipsTheOneWithout() throws {
    let plan = try plan()
    #expect(plan.accounts.count == 7)
    #expect(plan.skipped == [ImportPlan.Skip(line: 9, reason: "no Group/Title")])
  }

  @Test func aPlainLoginLikeTheSample() throws {
    let shop = try account("Example Shop", in: try plan())
    #expect(shop.username == "user@example.com")
    #expect(shop.email == "user@example.com")
    #expect(shop.password == "sample-password-1")
    #expect(shop.urls == [URL(string: "https://shop.example.com/account")])
    #expect(shop.notes == nil)  // the export's `""`
    #expect(shop.tags.isEmpty)
    #expect(shop.category == .login)
    #expect(shop.createdAt == (try utcDate("2025/02/14 13:39:24")))
  }

  @Test func theGroupPathBecomesATagAndDatesCarryOver() throws {
    let bank = try account("Example Bank", in: try plan())
    #expect(bank.tags == ["Finance/Banking"])
    #expect(bank.passwordChangedAt == (try utcDate("2025/06/01 09:00:00")))
    #expect(bank.expiresAt == (try utcDate("2026/06/01 09:00:00")))
    #expect(bank.urls.first?.query() == "next=home")
  }

  @Test func anEscapedDotStaysInTheTitleAndABareHostGetsHTTPS() throws {
    let shop = try account("Example.co.uk", in: try plan())
    #expect(shop.tags == ["Shopping"])
    #expect(shop.urls == [URL(string: "https://www.example.co.uk/signin")])
  }

  @Test func theTwoFactorKeyBecomesAOneTimeCode() throws {
    let mail = try account("Example Mail", in: try plan())
    let totp = try #require(mail.totp)
    #expect(totp == TOTPConfig(secret: try #require(Base32.decode("JBSWY3DPEHPK3PXP"))))
  }

  @Test func notesKeepLineBreaksAndQuotesAndHistoryCarriesOver() throws {
    let forum = try account("Example Forum", in: try plan())
    #expect(forum.notes == "line one\nline two with a \"quote\"")
    #expect(
      forum.passwordHistory == [
        PasswordHistoryEntry(
          password: "oldpass1", replacedAt: Date(timeIntervalSince1970: 0x6553_F100))
      ])
  }

  @Test func aNotesOnlyEntryIsASecureNote() throws {
    let note = try account("Wi-Fi at home", in: try plan())
    #expect(note.category == .secureNote)
    #expect(note.notes == "network: example-net\npassword in the drawer")
  }

  @Test func unmappedColumnsWithValuesAreReportedAndDefaultsAreNot() throws {
    let plan = try plan()
    #expect(plan.ignoredColumns == ["Run Command": 1])
    #expect(plan.warnings.isEmpty)
  }

  // MARK: - Format edges

  @Test func columnsAreFoundByNameInAnyOrderAndMayBeMissing() throws {
    let text = "Notes\tPassword\tGroup/Title\r\n\"a note\"\tpw\tOnly Three Columns\r\n"
    let plan = try PasswordSafeImport.plan(Data(text.utf8))
    let only = try #require(plan.accounts.first).payload
    #expect(only.title == "Only Three Columns")
    #expect(only.password == "pw")
    #expect(only.notes == "a note")
  }

  @Test func aByteOrderMarkIsIgnored() throws {
    let text = "\u{FEFF}Group/Title\tPassword\nBOM\tpw\n"
    #expect(try PasswordSafeImport.plan(Data(text.utf8)).accounts.first?.payload.title == "BOM")
  }

  @Test func somethingElseIsRefused() {
    #expect(throws: PasswordSafeImport.Failure.notPasswordSafeExport) {
      try PasswordSafeImport.plan(Data("name,url,username,password\n".utf8))
    }
    #expect(throws: PasswordSafeImport.Failure.notText) {
      try PasswordSafeImport.plan(Data([0xFF, 0xFE, 0x00, 0xD8]))
    }
  }

  @Test func aBadTwoFactorKeyOrHistoryIsAWarningNotALostAccount() throws {
    let text = "Group/Title\tPassword\tTwo Factor Key\tHistory\nOdd\tpw\tnot!base32\t1050zz\n"
    let plan = try PasswordSafeImport.plan(Data(text.utf8))
    let odd = try #require(plan.accounts.first).payload
    #expect(odd.password == "pw")
    #expect(odd.totp == nil)
    #expect(odd.passwordHistory.isEmpty)
    #expect(plan.warnings.count == 2)
  }

  @Test func historyParsesSeveralEntriesNewestFirst() throws {
    // two entries: t=0x10 "ab", t=0x20 "cde"
    let history = try #require(
      PasswordSafeImport.passwordHistory("1050200000010" + "0002ab" + "00000020" + "0003cde"))
    #expect(history.map(\.password) == ["cde", "ab"])
    #expect(PasswordSafeImport.passwordHistory("00000") == [])
    #expect(PasswordSafeImport.passwordHistory("105010000001") == nil)  // truncated
  }

  // MARK: - Duplicates and the bulk write

  @Test func duplicatesMatchTitleOrHostWithTheSameUser() throws {
    let plan = try plan()
    let existing = [
      AccountSummary(
        id: UUID(), title: "example shop", username: "USER@example.com", lastUpdated: Date()),
      AccountSummary(
        id: UUID(), title: "Bank (old)", username: "customer42", host: "bank.example.com",
        lastUpdated: Date()),
      AccountSummary(
        id: UUID(), title: "Example Mail", username: "someone-else", lastUpdated: Date()),
    ]
    let titles = plan.duplicates(of: existing).map { plan.accounts[$0].payload.title }
    #expect(Set(titles) == ["Example Shop", "Example Bank"])
  }

  @Test func importAccountsWritesThemAllInOneVerifiableTransaction() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-import-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    let password = Data("pw".utf8)
    let params = KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
    let repo = try await Vault.create(
      databasePath: path, password: password, params: params, deviceID: UUID())

    let payloads = try plan().accounts.map(\.payload)
    #expect(try await repo.importAccounts(payloads) == payloads.count)

    let reopened = try await Vault.unlock(databasePath: path, password: password, deviceID: UUID())
    let summaries = try await reopened.summaries()
    #expect(Set(summaries.map(\.title)) == Set(payloads.map(\.title)))
    let mail = try #require(summaries.first { $0.title == "Example Mail" })
    let stored = try #require(try await reopened.account(id: mail.id)).payload
    #expect(stored.totp != nil)
    #expect(stored.revisionHistory.first?.changed == ["imported"])
    #expect(stored.createdAt == (try utcDate("2025/03/01 10:00:00")))
  }
}
