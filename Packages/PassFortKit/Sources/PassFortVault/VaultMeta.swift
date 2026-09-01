import Foundation
import GRDB

/// The typed key/value store (§7.4): `header`, `manifest_mac`, `vault_version`,
/// `kdf_calibration`. One row per key in `vault_meta`; values are raw bytes, encoded
/// per key by the accessors below rather than by a single blanket convention.
enum VaultMetaKey: String {
  case header
  case manifestMAC = "manifest_mac"
  case vaultVersion = "vault_version"
  case kdfCalibration = "kdf_calibration"
}

enum VaultMeta {
  static func read(_ db: Database, _ key: VaultMetaKey) throws -> Data? {
    try Data.fetchOne(
      db, sql: "SELECT value FROM vault_meta WHERE key = ?", arguments: [key.rawValue])
  }

  static func write(_ db: Database, _ key: VaultMetaKey, _ value: Data) throws {
    try db.execute(
      sql: """
        INSERT INTO vault_meta (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
      arguments: [key.rawValue, value])
  }

  /// `vault_version` is stored as 8 raw bytes, big-endian -- the same canonical-int
  /// convention the header codec uses (`Canonical.hpp`), so a hex dump of the row
  /// reads the same way as the rest of the format. Missing means a brand-new vault
  /// (Phase 6 writes it on `create`), which is version 0.
  static func readVaultVersion(_ db: Database) throws -> UInt64 {
    guard let data = try read(db, .vaultVersion) else { return 0 }
    return data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
  }

  static func writeVaultVersion(_ db: Database, _ version: UInt64) throws {
    var be = version.bigEndian
    try write(db, .vaultVersion, withUnsafeBytes(of: &be) { Data($0) })
  }
}
