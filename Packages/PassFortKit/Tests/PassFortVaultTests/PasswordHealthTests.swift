import Foundation
import PassFortCrypto
import Testing

@testable import PassFortVault

@Suite struct PasswordHealthTests {

  // MARK: - Strength estimate

  @Test(arguments: ["password", "Password1!", "P@ssw0rd123", "hunter2", "123456", "qwerty123"])
  func commonPasswordsAreWeak(_ password: String) {
    #expect(PasswordStrength.estimate(password).score < PasswordAudit.weakBelow)
  }

  @Test(arguments: ["aaaaaaaaaaaa", "abcdefghijkl", "1234567890ab"])
  func repeatsAndSequencesAreWeak(_ password: String) {
    #expect(PasswordStrength.estimate(password).score < PasswordAudit.weakBelow)
  }

  @Test func aGeneratedPasswordIsStrong() throws {
    let generated = try PasswordPolicy().generate()
    #expect(PasswordStrength.estimate(generated).score == 4)
  }

  @Test func aLongPassphraseIsStrong() {
    #expect(PasswordStrength.estimate("correct horse battery staple").score == 4)
  }

  @Test func theEmptyPasswordScoresZero() {
    #expect(PasswordStrength.estimate("").score == 0)
  }

  @Test func effectiveLengthCollapsesRuns() {
    #expect(PasswordStrength.effectiveLength(Array("aaab")) == 2)  // "aaa" + "b"
    #expect(PasswordStrength.effectiveLength(Array("xqwertyx")) == 3)  // x + "qwerty" + x
    #expect(PasswordStrength.effectiveLength(Array("a1b2")) == 4)
  }

  @Test func splitCommonBaseUndoesLeetAndStripsTheTail() {
    #expect(PasswordStrength.splitCommonBase("P@ssw0rd123!") == ("password", "123!"))
    #expect(PasswordStrength.splitCommonBase("123456") == ("123456", ""))
  }

  // MARK: - Audit

  private let now = Date(timeIntervalSince1970: 2_000_000_000)
  private let day: TimeInterval = 24 * 3600

  private func account(
    _ title: String, password: String? = nil, changed: Date? = nil, expires: Date? = nil,
    url: String? = nil, deleted: Bool = false
  ) -> Account {
    var payload = AccountPayload(title: title, password: password)
    payload.createdAt = now.addingTimeInterval(-10 * day)
    payload.passwordChangedAt = changed
    payload.expiresAt = expires
    payload.urls = url.flatMap(URL.init(string:)).map { [$0] } ?? []
    return Account(
      id: UUID(), version: 1,
      updatedAt: HLC(wallMillis: 0, counter: 0, deviceID: UUID()), isDeleted: deleted,
      payload: payload, schemaVersion: 1, sealedSize: 0)
  }

  private func kinds(_ findings: [AuditFinding], for account: Account) -> [AuditFinding.Kind] {
    findings.filter { $0.account == account.id }.map(\.kind)
  }

  @Test func aHealthyAccountHasNoFindings() {
    let fine = account("fine", password: "Vx9#kQ2!mZ7@pL4$", url: "https://example.com")
    #expect(PasswordAudit.run([fine], now: now).isEmpty)
  }

  @Test func reuseIsReportedOnEveryAccountSharingThePassword() {
    let a = account("a", password: "Vx9#kQ2!mZ7@pL4$")
    let b = account("b", password: "Vx9#kQ2!mZ7@pL4$")
    let c = account("c", password: "Different#9kQ2!mZ")
    let findings = PasswordAudit.run([a, b, c], now: now)
    #expect(kinds(findings, for: a) == [.reused(count: 2)])
    #expect(kinds(findings, for: b) == [.reused(count: 2)])
    #expect(kinds(findings, for: c).isEmpty)
  }

  @Test func aDeletedAccountNeitherIsAuditedNorCountsTowardReuse() {
    let live = account("live", password: "Vx9#kQ2!mZ7@pL4$")
    let gone = account("gone", password: "Vx9#kQ2!mZ7@pL4$", deleted: true)
    #expect(PasswordAudit.run([live, gone], now: now).isEmpty)
  }

  @Test func oldExpiredExpiringAndHTTPAreReported() {
    let changed = now.addingTimeInterval(-400 * day)
    let old = account("old", password: "Vx9#kQ2!mZ7@pL4$", changed: changed)
    let expiredOn = now.addingTimeInterval(-day)
    let expired = account("expired", expires: expiredOn)
    let soonOn = now.addingTimeInterval(10 * day)
    let soon = account("soon", expires: soonOn)
    let http = account("http", url: "http://example.com")
    let findings = PasswordAudit.run([old, expired, soon, http], now: now)

    #expect(kinds(findings, for: old) == [.old(since: changed)])
    #expect(kinds(findings, for: expired) == [.expired(on: expiredOn)])
    #expect(kinds(findings, for: soon) == [.expiringSoon(on: soonOn)])
    #expect(kinds(findings, for: http) == [.insecureURL])
  }

  @Test func aWeakPasswordIsReportedWithItsScore() {
    let weak = account("weak", password: "password")
    guard case .weak(let score) = kinds(PasswordAudit.run([weak], now: now), for: weak).first
    else {
      Issue.record("expected a weak finding")
      return
    }
    #expect(score < PasswordAudit.weakBelow)
  }

  @Test func theRepositoryAuditsTheLiveVault() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-audit-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let repo = try await Vault.create(
      databasePath: dir.appending(path: "v.sqlite").path(percentEncoded: false),
      password: Data("pw".utf8),
      params: KdfParameters(
        kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16)),
      deviceID: UUID())

    let weak = try await repo.create(AccountPayload(title: "weak", password: "password"))
    _ = try await repo.create(AccountPayload(title: "fine", password: "Vx9#kQ2!mZ7@pL4$"))
    let findings = try await repo.audit()
    #expect(findings.map(\.account) == [weak.id])
  }
}
