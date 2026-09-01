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

  @Test func freshDatabaseReachesSchemaV1() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let vault = try VaultDatabase(
      path: dir.appending(path: "v.sqlite").path(percentEncoded: false))

    try vault.dbQueue.read { db in
      #expect(try db.tableExists("records"))
      #expect(try db.tableExists("vault_meta"))
      #expect(try db.tableExists("schema_version"))
      #expect(try Int.fetchOne(db, sql: "SELECT version FROM schema_version") == 1)

      let columns = Set(try db.columns(in: "records").map(\.name))
      #expect(
        columns == [
          "uuid", "version", "sealed", "is_deleted", "updated_at", "idx_title", "idx_url",
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
    #expect(applied == ["v1"])
  }

  /// Run once, deliberately: `PF_REGEN_FIXTURES=1 swift test`. Produces the
  /// checked-in fixture from the current schema. Never run in CI.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["PF_REGEN_FIXTURES"] == "1"))
  func regenerateV1Fixture() throws {
    let out = Self.fixturesDir.appending(path: "v1/vault.sqlite")
    try FileManager.default.createDirectory(
      at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    let path = out.path(percentEncoded: false)
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(atPath: path + suffix)
    }

    let vault = try VaultDatabase(path: path)
    try vault.dbQueue.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
    }
    for suffix in ["-wal", "-shm"] {
      try? FileManager.default.removeItem(atPath: path + suffix)
    }
  }
}
