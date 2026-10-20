import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

@Suite struct VaultBackupTests {

  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }

  private let device = UUID(uuid: (7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7))
  private let password = Data("correct horse".utf8)

  private struct Scratch {
    let dir: URL
    func path(_ name: String) -> String { dir.appending(path: name).path(percentEncoded: false) }
    func url(_ name: String) -> URL { dir.appending(path: name) }
    func remove() { try? FileManager.default.removeItem(at: dir) }
  }

  private func makeScratch() throws -> Scratch {
    let dir = FileManager.default.temporaryDirectory.appending(
      path: "pf-backup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return Scratch(dir: dir)
  }

  /// Create a vault with `count` accounts. The repository is returned so the caller decides
  /// whether the connection (and its un-checkpointed WAL) stays open.
  private func makeVault(at path: String, accounts count: Int) async throws -> VaultRepository {
    let repo = try await Vault.create(
      databasePath: path, password: password, params: fastParams, deviceID: device)
    for i in 0..<count {
      _ = try await repo.create(AccountPayload(title: "acct-\(i)", username: "u", password: "p"))
    }
    return repo
  }

  /// Open, add one account, and let the repository go -- closes the connection.
  private func addAccountAndClose(at path: String, title: String) async throws {
    let repo = try await Vault.unlock(databasePath: path, password: password, deviceID: device)
    _ = try await repo.create(AccountPayload(title: title, username: "u", password: "p"))
  }

  private func count(at path: String) async throws -> Int {
    try await Vault.unlock(databasePath: path, password: password, deviceID: device)
      .summaries().filter { !$0.isDeleted }.count
  }

  /// Unlocking writes a `.hw` sidecar next to the file, so check a copy, not the backup.
  private func unlockableCopyCount(of url: URL, in scratch: Scratch) async throws -> Int {
    let copy = scratch.path("check-\(UUID().uuidString).sqlite")
    try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: copy))
    return try await count(at: copy)
  }

  // MARK: - create

  @Test func backupCapturesRecordsStillInTheWal() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    let repo = try await makeVault(at: live, accounts: 3)  // stays open: WAL not checkpointed

    let wal = try FileManager.default.attributesOfItem(atPath: live + "-wal")[.size] as? Int ?? 0
    #expect(wal > 0)

    let dest = s.url("backup.sqlite")
    let info = try VaultBackup.create(databasePath: live, to: dest)

    #expect(try await unlockableCopyCount(of: dest, in: s) == 3)
    #expect(info.vaultVersion > 0)
    _ = repo
  }

  @Test func backupIsOneFileAndAVault() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    let repo = try await makeVault(at: live, accounts: 1)
    let folder = s.url("out")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    try VaultBackup.create(databasePath: live, to: folder.appending(path: "b.sqlite"))

    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path()) == ["b.sqlite"])
    #expect(Vault.exists(databasePath: folder.appending(path: "b.sqlite").path()))
    _ = repo
  }

  @Test func infoMatchesTheLiveVaultAndTheCryptoCoresUUID() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    let repo = try await makeVault(at: live, accounts: 2)

    let info = try VaultBackup.create(databasePath: live, to: s.url("b.sqlite"))

    // The header-offset read must agree with what C++ decodes.
    let session = try VaultSession.open(header: try await repo.header(), password: password)
    #expect(try await session.vaultUUID() == info.vaultID)
    #expect(VaultBackup.inspect(s.url("b.sqlite")) == info)
  }

  @Test func aBackupContainsNoPlaintextAndNoAntiRollbackMark() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    let repo = try await Vault.create(
      databasePath: live, password: password, params: fastParams, deviceID: device)
    _ = try await repo.create(
      AccountPayload(
        title: "ZZ-distinctive-title", username: "ZZ-distinctive-user",
        password: "ZZ-distinctive-secret"))
    let folder = s.url("out")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    try VaultBackup.create(databasePath: live, to: folder.appending(path: "b.sqlite"))

    let bytes = try Data(contentsOf: folder.appending(path: "b.sqlite"))
    for needle in ["ZZ-distinctive-title", "ZZ-distinctive-user", "ZZ-distinctive-secret"] {
      #expect(bytes.range(of: Data(needle.utf8)) == nil, "\(needle) leaked into the backup")
    }
    #expect(bytes.range(of: Data("correct horse".utf8)) == nil)  // nor the master password
    // The high-water mark is local state and must not travel with a backup.
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path()) == ["b.sqlite"])
    _ = repo
  }

  @Test func neverOverwritesAnExistingBackup() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    let repo = try await makeVault(at: live, accounts: 1)
    let dest = s.url("b.sqlite")

    try VaultBackup.create(databasePath: live, to: dest)
    #expect(throws: VaultBackup.Failure.destinationExists(dest.path(percentEncoded: false))) {
      try VaultBackup.create(databasePath: live, to: dest)
    }
    _ = repo
  }

  @Test func refusesASourceThatIsNotAVaultAndCreatesNothing() throws {
    let s = try makeScratch()
    defer { s.remove() }
    #expect(throws: VaultBackup.Failure.notAVault) {
      try VaultBackup.create(databasePath: s.path("missing.sqlite"), to: s.url("b.sqlite"))
    }
    #expect(!FileManager.default.fileExists(atPath: s.path("b.sqlite")))
  }

  @Test func backupTakenWhileWritesAreInFlightIsAlwaysConsistent() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    let repo = try await makeVault(at: live, accounts: 1)
    let folder = s.url("out")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for i in 0..<15 {
          _ = try await repo.create(
            AccountPayload(title: "w-\(i)", username: "u", password: "p"))
        }
      }
      group.addTask {
        for n in 0..<5 {
          try VaultBackup.create(
            databasePath: live, to: folder.appending(path: "b\(n).sqlite"))
        }
      }
      try await group.waitForAll()
    }

    // Unlock verifies the manifest MAC: a torn snapshot (row without its MAC) would throw.
    for n in 0..<5 {
      let seen = try await unlockableCopyCount(of: folder.appending(path: "b\(n).sqlite"), in: s)
      #expect((1...16).contains(seen))
    }
  }

  // MARK: - inspect

  @Test func inspectRejectsNonVaults() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    let repo = try await makeVault(at: live, accounts: 1)
    let good = s.url("good.sqlite")
    try VaultBackup.create(databasePath: live, to: good)

    #expect(VaultBackup.inspect(s.url("missing.sqlite")) == nil)

    try Data("not a database at all".utf8).write(to: s.url("random.sqlite"))
    #expect(VaultBackup.inspect(s.url("random.sqlite")) == nil)

    let bytes = try Data(contentsOf: good)
    try bytes.prefix(bytes.count / 2).write(to: s.url("truncated.sqlite"))
    #expect(VaultBackup.inspect(s.url("truncated.sqlite")) == nil)

    // A valid SQLite file without a PassFort header row.
    let plain = try DatabaseQueue(path: s.path("plain.sqlite"))
    try await plain.write { try $0.execute(sql: "CREATE TABLE t (x)") }
    #expect(VaultBackup.inspect(s.url("plain.sqlite")) == nil)
    _ = repo
  }

  @Test func inspectRejectsABadMagic() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    let repo = try await makeVault(at: live, accounts: 1)
    let bad = s.url("bad.sqlite")
    try VaultBackup.create(databasePath: live, to: bad)

    let queue = try DatabaseQueue(path: bad.path(percentEncoded: false))
    try await queue.write {
      try $0.execute(
        sql: "UPDATE vault_meta SET value = X'00' || substr(value, 2) WHERE key = 'header'")
    }
    #expect(VaultBackup.inspect(bad) == nil)
    _ = repo
  }

  // MARK: - naming and prune

  @Test func fileNamesSortChronologicallyAndCarryTheVaultID() {
    let id = UUID()
    let early = VaultBackup.fileName(vaultID: id, at: Date(timeIntervalSince1970: 1_700_000_000))
    let late = VaultBackup.fileName(vaultID: id, at: Date(timeIntervalSince1970: 1_800_000_000))
    #expect(early < late)
    #expect(early.hasPrefix("passfort-vault-\(id.uuidString.lowercased())-"))
    #expect(early == "passfort-vault-\(id.uuidString.lowercased())-20231114T221320Z.sqlite")
  }

  @Test func theDateRoundTripsThroughTheFileName() {
    let id = UUID()
    let taken = Date(timeIntervalSince1970: 1_700_000_000)
    let name = VaultBackup.fileName(vaultID: id, at: taken)

    #expect(VaultBackup.date(inFileName: name) == taken)
    #expect(VaultBackup.date(inFileName: "vault.sqlite") == nil)
    #expect(VaultBackup.date(inFileName: "passfort-vault-\(id.uuidString)-nonsense.sqlite") == nil)
    #expect(
      VaultBackup.date(inFileName: "passfort-vault-\(id.uuidString)-20231114T221320Z.txt") == nil)
  }

  @Test func pruneKeepsTheNewestAndTouchesOnlyThisVaultsBackups() throws {
    let s = try makeScratch()
    defer { s.remove() }
    let mine = UUID()
    let other = UUID()
    let days: [Double] = [0, 1, 2, 3, 4].map { 1_700_000_000 + $0 * 86_400 }
    var mineNames: [String] = []
    for t in days {
      let name = VaultBackup.fileName(vaultID: mine, at: Date(timeIntervalSince1970: t))
      mineNames.append(name)
      try Data().write(to: s.url(name))
    }
    let otherName = VaultBackup.fileName(
      vaultID: other, at: Date(timeIntervalSince1970: 1_700_000_000))
    try Data().write(to: s.url(otherName))
    try Data().write(to: s.url("notes.txt"))

    let removed = try VaultBackup.prune(in: s.dir, vaultID: mine, keep: 2)

    #expect(Set(removed) == Set(mineNames.prefix(3)))
    let left = Set(try FileManager.default.contentsOfDirectory(atPath: s.dir.path()))
    #expect(left == Set(mineNames.suffix(2) + [otherName, "notes.txt"]))
  }

  @Test func backupsListsOnlyThisVaultsFilesNewestFirst() throws {
    let s = try makeScratch()
    defer { s.remove() }
    let mine = UUID()
    let other = UUID()
    let times: [Double] = [1_700_000_000, 1_700_100_000, 1_700_050_000]
    for t in times {
      try Data().write(
        to: s.url(VaultBackup.fileName(vaultID: mine, at: Date(timeIntervalSince1970: t))))
    }
    try Data().write(to: s.url(VaultBackup.fileName(vaultID: other, at: .now)))
    try Data().write(to: s.url("notes.txt"))

    let listed = try VaultBackup.backups(in: s.dir, vaultID: mine).map(\.lastPathComponent)

    let expected = times.sorted(by: >).map {
      VaultBackup.fileName(vaultID: mine, at: Date(timeIntervalSince1970: $0))
    }
    #expect(listed == expected)
    #expect(try VaultBackup.backups(in: s.url("nope"), vaultID: mine).isEmpty)
  }

  @Test func pruneNeverDeletesEverythingAndToleratesAMissingFolder() throws {
    let s = try makeScratch()
    defer { s.remove() }
    let id = UUID()
    let name = VaultBackup.fileName(vaultID: id, at: .now)
    try Data().write(to: s.url(name))

    #expect(try VaultBackup.prune(in: s.dir, vaultID: id, keep: 0).isEmpty)
    #expect(FileManager.default.fileExists(atPath: s.path(name)))
    #expect(try VaultBackup.prune(in: s.url("nope"), vaultID: id, keep: 3).isEmpty)
  }

  // MARK: - restore

  @Test func restoreRoundTripsAndKeepsThePreviousVaultAside() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    do { _ = try await makeVault(at: live, accounts: 2) }  // closed on scope exit
    let backup = s.url("backup.sqlite")
    try VaultBackup.create(databasePath: live, to: backup)

    try await addAccountAndClose(at: live, title: "added-after-backup")
    #expect(try await count(at: live) == 3)

    let aside = try VaultBackup.restore(from: backup, toDatabasePath: live)

    // The anti-rollback mark remembers version 3; the restored file is older.
    do {
      _ = try await Vault.unlock(databasePath: live, password: password, deviceID: device)
      Issue.record("unlock should have reported a rollback")
    } catch VaultManifest.Failure.rollbackDetected {
    }
    try HighWaterMark(sidecarFor: live).reset()
    #expect(try await count(at: live) == 2)

    // Nothing was destroyed: the replaced vault is still there, with its third account.
    let movedAside = try #require(aside)
    #expect(Vault.exists(databasePath: movedAside.path(percentEncoded: false)))
    #expect(
      try await count(at: movedAside.path(percentEncoded: false)) == 3)
  }

  @Test func restoreRefusesAnotherVaultUnlessAllowed() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let a = s.path("a.sqlite")
    let b = s.path("b.sqlite")
    do {
      _ = try await makeVault(at: a, accounts: 1)
      _ = try await makeVault(at: b, accounts: 2)
    }
    let backupOfB = s.url("b-backup.sqlite")
    let infoB = try VaultBackup.create(databasePath: b, to: backupOfB)
    let infoA = try #require(VaultBackup.inspect(URL(fileURLWithPath: a)))

    #expect(
      throws: VaultBackup.Failure.differentVault(backup: infoB.vaultID, live: infoA.vaultID)
    ) {
      try VaultBackup.restore(from: backupOfB, toDatabasePath: a)
    }
    #expect(try await count(at: a) == 1)  // untouched

    try VaultBackup.restore(from: backupOfB, toDatabasePath: a, allowDifferentVault: true)
    try HighWaterMark(sidecarFor: a).reset()
    #expect(try await count(at: a) == 2)
  }

  @Test func restoreRejectsANonVaultBackupAndLeavesTheLiveVaultAlone() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    do { _ = try await makeVault(at: live, accounts: 2) }
    try Data("junk".utf8).write(to: s.url("junk.sqlite"))

    #expect(throws: VaultBackup.Failure.notAVault) {
      try VaultBackup.restore(from: s.url("junk.sqlite"), toDatabasePath: live)
    }
    #expect(try await count(at: live) == 2)
    let names = try FileManager.default.contentsOfDirectory(atPath: s.dir.path())
    #expect(!names.contains { $0.contains("pre-restore") || $0.hasSuffix(".restoring") })
  }

  @Test func restoreWithNoLiveVaultInstallsTheBackupAndCreatesTheFolder() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let source = s.path("source.sqlite")
    do { _ = try await makeVault(at: source, accounts: 2) }
    let backup = s.url("backup.sqlite")
    try VaultBackup.create(databasePath: source, to: backup)

    let fresh = s.path("new-machine/PassFort/vault.sqlite")
    let aside = try VaultBackup.restore(from: backup, toDatabasePath: fresh)

    #expect(aside == nil)
    #expect(try await count(at: fresh) == 2)  // no .hw yet, so no rollback prompt
  }
}
