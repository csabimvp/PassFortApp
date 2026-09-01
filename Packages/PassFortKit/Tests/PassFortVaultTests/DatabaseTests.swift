import Foundation
import GRDB
import Testing

@testable import PassFortVault

@Suite struct DatabaseTests {

  private func tempVaultPath() throws -> (dir: URL, path: String) {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "pf-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (dir, dir.appending(path: "vault.sqlite").path(percentEncoded: false))
  }

  @Test func createsWALDatabaseWithRestrictedPermissions() throws {
    let (dir, path) = try tempVaultPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    let vault = try VaultDatabase(path: path)

    let journalMode = try vault.dbQueue.read { db in
      try String.fetchOne(db, sql: "PRAGMA journal_mode")
    }
    #expect(journalMode == "wal")

    let sync = try vault.dbQueue.read { db in
      try Int.fetchOne(db, sql: "PRAGMA synchronous")
    }
    #expect(sync == 2)  // 2 == FULL

    let perms = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]
    #expect((perms as? NSNumber)?.int16Value == 0o600)
  }

  @Test func reopeningTheSameFileSucceeds() throws {
    let (dir, path) = try tempVaultPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    _ = try VaultDatabase(path: path)
    _ = try VaultDatabase(path: path)  // migrator is idempotent
  }
}
