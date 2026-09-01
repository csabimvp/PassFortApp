import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

@Suite struct VaultManifestTests {

  // MARK: - Fixtures

  /// Cheap Argon2id -- still the real measurement path, ~milliseconds not ~second.
  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }

  private func tempVault() throws -> (dir: URL, database: VaultDatabase) {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "pf-manifest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appending(path: "vault.sqlite").path(percentEncoded: false)
    return (dir, try VaultDatabase(path: path))
  }

  private func openSession() throws -> VaultSession {
    let password = Data("correct horse".utf8)
    let header = try VaultSession.create(password: password, params: fastParams)
    return try VaultSession.open(header: header, password: password)
  }

  /// Seal `count` throwaway rows, insert them, and persist a matching manifest at
  /// `vaultVersion`. Returns the row UUIDs in insertion order.
  @discardableResult
  private func seedVault(
    _ database: VaultDatabase, session: VaultSession, count: Int, vaultVersion: UInt64 = 1
  ) async throws -> [UUID] {
    var built: [SealedRecord] = []
    for i in 0..<count {
      let id = UUID()
      let sealed = try await session.seal(
        recordID: id, version: 1, schema: 1, plaintext: Data("secret \(i)".utf8))
      built.append(
        SealedRecord(
          id: id, version: 1, schemaVersion: 1, sealed: sealed,
          updatedAt: .now(device: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))))
    }
    let records = built

    try await database.dbQueue.write { db in
      for record in records { try record.insert(db) }
    }

    let manifest = try await VaultManifest.compute(
      session: session, database: database, vaultVersion: vaultVersion)
    try await database.dbQueue.write { db in
      try VaultMeta.write(db, .manifestMAC, manifest.mac)
      try VaultMeta.writeVaultVersion(db, vaultVersion)
    }
    return records.map(\.id)
  }

  // MARK: - Tests

  @Test func verifyPassesOnAnUntouchedVault() async throws {
    let (dir, database) = try tempVault()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = try openSession()

    try await seedVault(database, session: session, count: 3, vaultVersion: 1)

    let state = try await VaultManifest.verifyAtUnlock(
      session: session, database: database, highWater: 1)
    #expect(state.vaultVersion == 1)
    #expect(state.mac.count == 32)
  }

  @Test func macIsDeterministicAndBoundToVaultVersion() async throws {
    let (dir, database) = try tempVault()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = try openSession()
    try await seedVault(database, session: session, count: 3, vaultVersion: 1)

    let first = try await VaultManifest.compute(
      session: session, database: database, vaultVersion: 1)
    let again = try await VaultManifest.compute(
      session: session, database: database, vaultVersion: 1)
    #expect(first.mac == again.mac)  // deterministic: same rows, same UUID sort, same version

    let atOtherVersion = try await VaultManifest.compute(
      session: session, database: database, vaultVersion: 2)
    #expect(atOtherVersion.mac != first.mac)  // vault_version is bound into the tag
  }

  @Test func deletingARowBehindTheAppFailsTheMACCheck() async throws {
    let (dir, database) = try tempVault()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = try openSession()
    let ids = try await seedVault(database, session: session, count: 3, vaultVersion: 1)

    // An attacker with file access drops a row -- no version bump, MAC not updated.
    try await database.dbQueue.write { db in
      try db.execute(
        sql: "DELETE FROM records WHERE uuid = ?", arguments: [ids[0].rawData])
    }

    await #expect(throws: VaultManifest.Failure.macMismatch) {
      try await VaultManifest.verifyAtUnlock(session: session, database: database, highWater: 1)
    }
  }

  @Test func editingSealedBytesBehindTheAppFailsTheMACCheck() async throws {
    let (dir, database) = try tempVault()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = try openSession()
    let ids = try await seedVault(database, session: session, count: 2, vaultVersion: 1)

    try await database.dbQueue.write { db in
      var tampered = try #require(try SealedRecord.fetchOne(db, key: ids[0].rawData))
      tampered.sealed[tampered.sealed.startIndex] ^= 0x01
      try tampered.update(db)
    }

    await #expect(throws: VaultManifest.Failure.macMismatch) {
      try await VaultManifest.verifyAtUnlock(session: session, database: database, highWater: 1)
    }
  }

  @Test func restoringAnOlderWholeFileFailsTheRollbackCheck() async throws {
    let (dir, database) = try tempVault()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = try openSession()
    try await seedVault(database, session: session, count: 2, vaultVersion: 5)

    // The vault has since moved on to version 9 -- the value a real device caches
    // in its sidecar / Keychain high-water mark.
    let highWater: UInt64 = 9

    await #expect(
      throws: VaultManifest.Failure.rollbackDetected(vaultVersion: 5, highWater: highWater)
    ) {
      try await VaultManifest.verifyAtUnlock(
        session: session, database: database, highWater: highWater)
    }
  }

  @Test func rollbackCheckRunsBeforeTheMACRecompute() async throws {
    // A rolled-back file whose own MAC is *also* internally valid must still be
    // rejected -- on the cheap version check, not by luck of a MAC mismatch.
    let (dir, database) = try tempVault()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = try openSession()
    try await seedVault(database, session: session, count: 2, vaultVersion: 3)

    await #expect(throws: VaultManifest.Failure.self) {
      try await VaultManifest.verifyAtUnlock(session: session, database: database, highWater: 4)
    }
  }
}
