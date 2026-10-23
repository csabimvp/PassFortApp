import Foundation
import GRDB
import Testing

@testable import PassFortVault

@Suite struct MigrationTests {

  static let fixturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Fixtures")

  private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-mig-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  @Test func freshDatabaseReachesSchemaV2() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let vault = try VaultDatabase(
      path: dir.appending(path: "v.sqlite").path(percentEncoded: false))

    try vault.dbQueue.read { db in
      #expect(try db.tableExists("records"))
      #expect(try db.tableExists("vault_meta"))
      #expect(try db.tableExists("schema_version"))
      // v2 is a schema change, not a format change: schema_version stays 1 (A.5).
      #expect(try Int.fetchOne(db, sql: "SELECT version FROM schema_version") == 1)
      #expect(try Set(String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")) == ["v1", "v2"])

      let columns = Set(try db.columns(in: "records").map(\.name))
      #expect(
        columns == [
          "uuid", "version", "sealed", "is_deleted", "updated_at", "idx_title", "idx_url",
          "hlc_counter", "hlc_device", "synced_version", "synced_seq",
        ])
    }
  }

  /// The §8.2 / §13.4 rule: every migration is tested against a checked-in
  /// fixture vault, and the fixtures are never regenerated.
  @Test func checkedInV1FixtureStillMigrates() throws {
    let source = Self.fixturesDir.appending(path: "v1/vault.sqlite")
    try #require(
      FileManager.default.fileExists(atPath: source.path(percentEncoded: false)),
      "missing v1 fixture -- regenerate with PF_REGEN_FIXTURES=1 swift test")

    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let destination = dir.appending(path: "vault.sqlite").path(percentEncoded: false)
    try FileManager.default.copyItem(
      atPath: source.path(percentEncoded: false), toPath: destination)

    let vault = try VaultDatabase(path: destination)
    let applied = try vault.dbQueue.read { db in
      try Set(String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations"))
    }
    #expect(applied == ["v1", "v2"])
  }

  // MARK: - v1 -> v2 with records (m5-sync.md Phase 6)

  /// `Fixtures/v1-records`: three records sealed by the v1 build (one at version 1, one at 2, a
  /// tombstone at 2), `vault_version` 5. Its README has the password and how it was made.
  @Test func v1RecordsFixtureMigratesWithEveryRowDirtyAndTheManifestIntact() async throws {
    let source = Self.fixturesDir.appending(path: "v1-records/vault.sqlite")
    try #require(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "vault.sqlite").path(percentEncoded: false)
    try FileManager.default.copyItem(atPath: source.path(percentEncoded: false), toPath: path)
    let mark = HighWaterMark(url: dir.appending(path: "vault.hw"))
    try mark.write(5)

    // `unlock` migrates, then verifies the manifest MAC and the mark: v2 must not have touched a
    // byte the MAC covers.
    let device = UUID()
    let repo = try await Vault.unlock(
      databasePath: path, password: Data("fixture-v1-password".utf8), deviceID: device,
      highWater: mark)

    // `Row` isn't Sendable: take the four new columns out as plain values inside the read.
    let rows = try await VaultDatabase(path: path).dbQueue.read { db in
      try Row.fetchAll(
        db, sql: "SELECT hlc_counter, hlc_device, synced_version, synced_seq FROM records"
      ).map { row in
        (
          counter: row["hlc_counter"] as Int64, device: row["hlc_device"] as Data,
          syncedVersion: row["synced_version"] as Int64?, syncedSeq: row["synced_seq"] as Int64?
        )
      }
    }
    #expect(rows.count == 3)
    for row in rows {
      #expect(row.counter == 0)
      #expect(row.device == Data(count: 16))
      #expect(row.syncedVersion == nil)
      #expect(row.syncedSeq == nil)
    }

    let dirty = try await repo.dirtyRecords()
    #expect(dirty.count == 3, "a pre-sync vault is all dirty: enabling sync pushes everything")
    #expect(dirty.allSatisfy { $0.syncedVersion == nil && $0.updatedAt.counter == 0 })

    // Every record still opens, at the version it was sealed at.
    let summaries = try await repo.summaries()
    #expect(Set(summaries.map(\.title)) == ["Example Mail", "Example Bank", "Old Forum"])
    let byTitle = Dictionary(uniqueKeysWithValues: summaries.map { ($0.title, $0) })
    #expect(byTitle["Old Forum"]?.isDeleted == true)
    let bank = try #require(byTitle["Example Bank"])
    #expect(try await repo.account(id: bank.id)?.version == 2)

    // And the migrated vault takes writes, stamped by this device, after the v1 stamps.
    let newest = try #require(dirty.map(\.updatedAt).max())
    let edited = try await repo.update(id: bank.id) { $0.notes = "after v2" }
    #expect(edited.updatedAt > newest)
    #expect(edited.updatedAt.deviceID == device)
    #expect(try mark.read() == 6)
  }
}
