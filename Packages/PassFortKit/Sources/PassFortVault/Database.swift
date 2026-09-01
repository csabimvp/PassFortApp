import Foundation
import GRDB

/// The vault's SQLite database: one serialized connection (`DatabaseQueue`),
/// write-ahead logging, `synchronous = FULL`, and a `0600` file (architecture
/// §8.2). Every read and write in `PassFortVault` goes through this one queue,
/// so there is never a concurrent-writer problem to reason about.
public struct VaultDatabase {
  let dbQueue: DatabaseQueue

  public init(path: String) throws {
    try Self.prepareDirectory(for: path)

    var config = Configuration()
    config.prepareDatabase { db in
      // WAL: a crash mid-write leaves the main file intact; readers never block
      // a writer. FULL: fsync at every commit, so a returned write survives a
      // power cut -- the mid-write kill test (Phase 7) proves this holds with
      // the manifest update.
      try db.execute(sql: "PRAGMA journal_mode = WAL")
      try db.execute(sql: "PRAGMA synchronous = FULL")
      try db.execute(sql: "PRAGMA foreign_keys = ON")
    }
    dbQueue = try DatabaseQueue(path: path, configuration: config)

    try Self.restrictPermissions(path: path)
    try Self.migrator.migrate(dbQueue)
  }
}

// MARK: - Location and hardening

extension VaultDatabase {
  /// `~/Library/Application Support/PassFort/vault.sqlite` (§8.2).
  public static var defaultPath: String {
    URL.applicationSupportDirectory
      .appending(path: "PassFort/vault.sqlite")
      .path(percentEncoded: false)
  }

  private static func prepareDirectory(for path: String) throws {
    let dir = (path as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])

    // Keep the vault out of Spotlight (§8.2).
    let marker = (dir as NSString).appendingPathComponent(".metadata_never_index")
    if !FileManager.default.fileExists(atPath: marker) {
      FileManager.default.createFile(atPath: marker, contents: nil)
    }
  }

  private static func restrictPermissions(path: String) throws {
    for suffix in ["", "-wal", "-shm"] {
      let sidecar = path + suffix
      guard FileManager.default.fileExists(atPath: sidecar) else { continue }
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: sidecar)
    }
  }
}
