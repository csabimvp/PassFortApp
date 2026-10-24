import Foundation
import GRDB

/// The typed key/value store (§7.4): `header`, `manifest_mac`, `vault_version`,
/// `kdf_calibration`, and the sync keys (`m5-sync.md` A.5). One row per key in `vault_meta`;
/// values are raw bytes, encoded per key by the accessors below rather than by a single blanket
/// convention.
enum VaultMetaKey: String {
  case header
  case manifestMAC = "manifest_mac"
  case vaultVersion = "vault_version"
  case kdfCalibration = "kdf_calibration"
  /// JSON `SyncConfig` -- no secrets. Absent = sync is off.
  case syncConfig = "sync_config"
  /// u64 BE: the highest server `seq` fully ingested.
  case syncCursor = "sync_cursor"
  /// u64 BE: the server `headerVersion` this device's header corresponds to.
  case syncHeaderVersion = "sync_header_version"
  /// `0x01` while the local header has changed and the server hasn't got it.
  case headerDirty = "header_dirty"
  /// u64 BE `headerVersion` ‖ header bytes: a newer server header not yet adopted.
  case pendingHeader = "pending_header"
  /// u64 BE Unix milliseconds: when the last sync run finished. Status only.
  case syncLastSynced = "sync_last_synced"
}

/// Where this vault syncs (A.5). Written by enable / join, removed by disable.
struct SyncConfig: Codable, Equatable, Sendable {
  var endpoint: URL
  var vaultID: UUID
  var enabledAt: Date

  enum CodingKeys: String, CodingKey {
    case endpoint
    case vaultID = "vaultId"
    case enabledAt
  }
}

/// A header another device pushed, waiting for this device's next unlock to adopt it (A.8).
struct PendingHeader: Equatable, Sendable {
  var headerVersion: UInt64
  var header: Data
}

enum VaultMeta {
  static func read(_ db: Database, _ key: VaultMetaKey) throws -> Data? {
    try Data.fetchOne(
      db, sql: "SELECT value FROM vault_meta WHERE key = ?", arguments: [key.rawValue])
  }

  static func remove(_ db: Database, _ key: VaultMetaKey) throws {
    try db.execute(sql: "DELETE FROM vault_meta WHERE key = ?", arguments: [key.rawValue])
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
    return decodeU64(data)
  }

  static func writeVaultVersion(_ db: Database, _ version: UInt64) throws {
    try write(db, .vaultVersion, bigEndian(version))
  }

  // MARK: - Sync (A.5)

  static func readSyncConfig(_ db: Database) throws -> SyncConfig? {
    try read(db, .syncConfig).map { try JSONDecoder.syncConfig.decode(SyncConfig.self, from: $0) }
  }

  static func writeSyncConfig(_ db: Database, _ config: SyncConfig) throws {
    try write(db, .syncConfig, try JSONEncoder.syncConfig.encode(config))
  }

  /// Missing means nothing ingested yet: cursor 0, a pull from the start.
  static func readSyncCursor(_ db: Database) throws -> UInt64 {
    try readU64(db, .syncCursor) ?? 0
  }

  static func writeSyncCursor(_ db: Database, _ cursor: UInt64) throws {
    try write(db, .syncCursor, bigEndian(cursor))
  }

  /// Missing means this device's header has never been on the server.
  static func readSyncHeaderVersion(_ db: Database) throws -> UInt64? {
    try readU64(db, .syncHeaderVersion)
  }

  static func writeSyncHeaderVersion(_ db: Database, _ version: UInt64) throws {
    try write(db, .syncHeaderVersion, bigEndian(version))
  }

  static func readHeaderDirty(_ db: Database) throws -> Bool {
    try read(db, .headerDirty) == Data([0x01])
  }

  /// Set stores `0x01`; clear removes the row.
  static func writeHeaderDirty(_ db: Database, _ dirty: Bool) throws {
    if dirty { try write(db, .headerDirty, Data([0x01])) } else { try remove(db, .headerDirty) }
  }

  static func readPendingHeader(_ db: Database) throws -> PendingHeader? {
    guard let data = try read(db, .pendingHeader), data.count > 8 else { return nil }
    return PendingHeader(
      headerVersion: decodeU64(data.prefix(8)), header: Data(data.dropFirst(8)))
  }

  /// `nil` removes it (adopted, or superseded).
  static func writePendingHeader(_ db: Database, _ pending: PendingHeader?) throws {
    guard let pending else { return try remove(db, .pendingHeader) }
    try write(db, .pendingHeader, bigEndian(pending.headerVersion) + pending.header)
  }

  /// Store a header this device changed itself -- a recovery-key rotation, a password change, a
  /// recovery (A.8). With sync on it is also marked dirty, so the next run pushes it. A header
  /// adopted *from* the server is written with plain `write` instead.
  static func writeLocalHeader(_ db: Database, _ header: Data) throws {
    try write(db, .header, header)
    if try read(db, .syncConfig) != nil { try writeHeaderDirty(db, true) }
  }

  static func readSyncLastSynced(_ db: Database) throws -> Date? {
    try readU64(db, .syncLastSynced).map { Date(timeIntervalSince1970: Double($0) / 1000) }
  }

  static func writeSyncLastSynced(_ db: Database, _ date: Date) throws {
    try write(db, .syncLastSynced, bigEndian(UInt64(max(0, date.timeIntervalSince1970 * 1000))))
  }

  // MARK: - u64 big-endian

  /// 8 raw bytes, big-endian -- the canonical-int convention the header codec uses
  /// (`Canonical.hpp`), so a hex dump of the row reads like the rest of the format. A value of
  /// any other length reads as missing rather than as a wrong number.
  private static func readU64(_ db: Database, _ key: VaultMetaKey) throws -> UInt64? {
    guard let data = try read(db, key), data.count == 8 else { return nil }
    return decodeU64(data)
  }

  private static func decodeU64(_ bytes: Data) -> UInt64 {
    bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
  }

  private static func bigEndian(_ value: UInt64) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
  }
}

extension JSONEncoder {
  /// `sync_config`'s encoding: ISO 8601 dates, sorted keys, so the stored bytes are stable.
  fileprivate static var syncConfig: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .sortedKeys
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var syncConfig: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
