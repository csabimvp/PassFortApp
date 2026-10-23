import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

@Suite struct VaultImportTests {

  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }

  private let device = UUID(uuid: (7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7))
  private let sourcePassword = Data("dev vault".utf8)
  private let targetPassword = Data("everyday vault".utf8)

  private struct Scratch {
    let dir: URL
    func path(_ name: String) -> String { dir.appending(path: name).path(percentEncoded: false) }
    func remove() { try? FileManager.default.removeItem(at: dir) }
  }

  private func makeScratch() throws -> Scratch {
    let dir = FileManager.default.temporaryDirectory.appending(
      path: "pf-vault-import-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return Scratch(dir: dir)
  }

  private func makeTarget(_ scratch: Scratch) async throws -> VaultRepository {
    try await Vault.create(
      databasePath: scratch.path("target.sqlite"), password: targetPassword, params: fastParams,
      deviceID: device)
  }

  /// A source vault with three live accounts -- one with a changed password, one with a
  /// one-time code -- and one deleted. The repository is returned so the caller decides whether
  /// the connection (and its un-checkpointed WAL) stays open.
  private func makeSource(at path: String) async throws -> VaultRepository {
    let repo = try await Vault.create(
      databasePath: path, password: sourcePassword, params: fastParams, deviceID: device)
    let bank = try await repo.create(
      AccountPayload(title: "Bank", username: "me", password: "old"))
    _ = try await repo.update(id: bank.id) { $0.password = "new" }
    _ = try await repo.create(
      AccountPayload(
        title: "Mail", username: "me@example.com", password: "m",
        totp: try TOTPConfig(parsing: "JBSWY3DPEHPK3PXP")))
    _ = try await repo.create(AccountPayload(title: "Forum", username: "me", password: "f"))
    let junk = try await repo.create(AccountPayload(title: "Test junk", password: "x"))
    try await repo.delete(id: junk.id)
    return repo
  }

  // MARK: - The happy path

  @Test func importsLiveAccountsUnderNewIDsWithTheirPasswordHistory() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let sourcePath = scratch.path("dev.sqlite")
    let source = try await makeSource(at: sourcePath)
    let sourceIDs = Set(try await source.summaries().map(\.id))
    let target = try await makeTarget(scratch)

    let plan = try await VaultImport.plan(
      fromVaultAt: sourcePath, unlockingWith: .password(sourcePassword), into: target)
    #expect(plan.accounts.map(\.payload.title) == ["Bank", "Forum", "Mail"])
    #expect(plan.accounts.map(\.line) == [1, 2, 3])
    #expect(plan.warnings == ["1 deleted account is not offered"])
    #expect(plan.accounts.allSatisfy { $0.payload.revisionHistory.isEmpty })

    let bank = try #require(plan.accounts.first { $0.payload.title == "Bank" }).payload
    #expect(bank.password == "new")
    #expect(bank.passwordHistory.map(\.password) == ["old"])

    #expect(try await target.importAccounts(plan.accounts.map(\.payload)) == 3)
    let reopened = try await Vault.unlock(
      databasePath: scratch.path("target.sqlite"), password: targetPassword, deviceID: device)
    let summaries = try await reopened.summaries()
    #expect(Set(summaries.map(\.title)) == ["Bank", "Forum", "Mail"])
    #expect(Set(summaries.map(\.id)).isDisjoint(with: sourceIDs))
    let mail = try #require(summaries.first { $0.title == "Mail" })
    let stored = try #require(try await reopened.account(id: mail.id)).payload
    #expect(stored.totp != nil)
    #expect(stored.revisionHistory.map(\.changed) == [["imported"]])
  }

  @Test func leavesTheSourceFileAndItsMarkUntouched() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let sourcePath = scratch.path("dev.sqlite")
    _ = try await makeSource(at: sourcePath)  // dropped: the connection closes, WAL checkpointed
    let before = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
    let markBefore = try HighWaterMark(sidecarFor: sourcePath).read()
    let target = try await makeTarget(scratch)

    _ = try await VaultImport.plan(
      fromVaultAt: sourcePath, unlockingWith: .password(sourcePassword), into: target)

    #expect(try Data(contentsOf: URL(fileURLWithPath: sourcePath)) == before)
    #expect(try HighWaterMark(sidecarFor: sourcePath).read() == markBefore)
    // And it still opens as a vault in its own right.
    let reopened = try await Vault.unlock(
      databasePath: sourcePath, password: sourcePassword, deviceID: device)
    #expect(try await reopened.summaries().count == 4)
  }

  @Test func readsASourceThatIsStillOpenElsewhere() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let sourcePath = scratch.path("dev.sqlite")
    let source = try await makeSource(at: sourcePath)  // held: its writes may sit in the WAL
    let target = try await makeTarget(scratch)

    let plan = try await VaultImport.plan(
      fromVaultAt: sourcePath, unlockingWith: .password(sourcePassword), into: target)
    #expect(plan.accounts.count == 3)
    _ = try await source.create(AccountPayload(title: "Still writable"))
  }

  @Test func plannedDuplicatesAreTheOnesAlreadyInTheTarget() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let sourcePath = scratch.path("dev.sqlite")
    _ = try await makeSource(at: sourcePath)
    let target = try await makeTarget(scratch)
    _ = try await target.create(AccountPayload(title: "bank", username: "ME", password: "z"))

    let plan = try await VaultImport.plan(
      fromVaultAt: sourcePath, unlockingWith: .password(sourcePassword), into: target)
    let duplicates = plan.duplicates(of: try await target.summaries())
    #expect(duplicates.map { plan.accounts[$0].payload.title } == ["Bank"])
  }

  // MARK: - Credentials

  @Test func aWrongSourcePasswordIsAuthFailed() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let sourcePath = scratch.path("dev.sqlite")
    _ = try await makeSource(at: sourcePath)
    let target = try await makeTarget(scratch)

    await #expect(throws: PassFortError.authFailed) {
      try await VaultImport.plan(
        fromVaultAt: sourcePath, unlockingWith: .password(targetPassword), into: target)
    }
  }

  @Test func aRecoveryKeyOpensTheSourceWithoutConsumingTheSlot() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let sourcePath = scratch.path("dev.sqlite")
    let (source, key) = try await Vault.createWithRecovery(
      databasePath: sourcePath, password: sourcePassword, params: fastParams, deviceID: device)
    _ = try await source.create(AccountPayload(title: "Bank", password: "p"))
    let target = try await makeTarget(scratch)

    for _ in 0..<2 {
      let plan = try await VaultImport.plan(
        fromVaultAt: sourcePath, unlockingWith: .recoveryKey(key), into: target)
      #expect(plan.accounts.map(\.payload.title) == ["Bank"])
    }
  }

  @Test func aRecoveryKeyForAVaultWithoutASlotIsNotFound() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let sourcePath = scratch.path("dev.sqlite")
    _ = try await makeSource(at: sourcePath)
    let target = try await makeTarget(scratch)

    await #expect(throws: PassFortError.notFound) {
      try await VaultImport.plan(
        fromVaultAt: sourcePath, unlockingWith: .recoveryKey(.generate()), into: target)
    }
  }

  // MARK: - Refusals

  @Test func refusesTheTargetItselfAndACopyOfIt() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let target = try await makeTarget(scratch)
    let targetPath = scratch.path("target.sqlite")
    let copyPath = scratch.path("copy.sqlite")
    _ = try VaultBackup.create(databasePath: targetPath, to: URL(fileURLWithPath: copyPath))

    for path in [targetPath, copyPath] {
      await #expect(throws: VaultImport.Failure.sameVault) {
        try await VaultImport.plan(
          fromVaultAt: path, unlockingWith: .password(targetPassword), into: target)
      }
    }
  }

  @Test func refusesAMissingFileAndANonVault() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let target = try await makeTarget(scratch)
    let text = scratch.path("notes.txt")
    try Data("not a vault".utf8).write(to: URL(fileURLWithPath: text))

    for path in [scratch.path("missing.sqlite"), text] {
      await #expect(throws: VaultImport.Failure.notAVault) {
        try await VaultImport.plan(
          fromVaultAt: path, unlockingWith: .password(sourcePassword), into: target)
      }
    }
  }

  @Test func refusesASourceEditedOutsidePassFort() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let sourcePath = scratch.path("dev.sqlite")
    let ids = try await makeSource(at: sourcePath).summaries().map(\.id)
    try await DatabaseQueue(path: sourcePath).write { db in
      try db.execute(sql: "DELETE FROM records WHERE uuid = ?", arguments: [ids[0].rawData])
    }
    let target = try await makeTarget(scratch)

    await #expect(throws: VaultManifest.Failure.macMismatch) {
      try await VaultImport.plan(
        fromVaultAt: sourcePath, unlockingWith: .password(sourcePassword), into: target)
    }
  }

  @Test func refusesASourceFromALaterSchema() async throws {
    let scratch = try makeScratch()
    defer { scratch.remove() }
    let sourcePath = scratch.path("dev.sqlite")
    _ = try await makeSource(at: sourcePath)
    try await DatabaseQueue(path: sourcePath).write { db in
      try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v999')")
    }
    let target = try await makeTarget(scratch)

    await #expect(throws: VaultImport.Failure.unsupportedSchema) {
      try await VaultImport.plan(
        fromVaultAt: sourcePath, unlockingWith: .password(sourcePassword), into: target)
    }
  }
}
