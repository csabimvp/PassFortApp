import Foundation
import GRDB

/// The envelope — the plaintext columns of a `records` row (§7.1). Everything SQL
/// can filter on and sync can move; nothing §3.1 rates above "Low". `sealed` is
/// opaque, straight out of `pf_seal`.
public struct SealedRecord: Sendable, Identifiable, Equatable {
  public var id: UUID  // records PRIMARY KEY == account_id
  public var version: UInt64  // monotonic; bound into the AEAD AAD (§5.4)
  public var schemaVersion: UInt16  // §7.1: for M2 the vault-wide schema_version value
  public var sealed: Data  // nonce ‖ ciphertext ‖ tag
  public var isDeleted: Bool  // tombstone; the row survives until every device acks
  public var updatedAt: HLC  // conflict clock (§9.3) -- MUST stay plaintext
  public var blindTitle: Data?  // idx_title -- keyed blind index, deferred (§14 #20)
  public var blindURL: Data?  // idx_url
  /// The version the sync server last confirmed; `nil` = never on the server (A.5).
  public var syncedVersion: UInt64?
  /// The server `seq` of `syncedVersion`.
  public var syncedSeq: UInt64?

  public init(
    id: UUID, version: UInt64, schemaVersion: UInt16, sealed: Data, isDeleted: Bool = false,
    updatedAt: HLC, blindTitle: Data? = nil, blindURL: Data? = nil, syncedVersion: UInt64? = nil,
    syncedSeq: UInt64? = nil
  ) {
    self.id = id
    self.version = version
    self.schemaVersion = schemaVersion
    self.sealed = sealed
    self.isDeleted = isDeleted
    self.updatedAt = updatedAt
    self.blindTitle = blindTitle
    self.blindURL = blindURL
    self.syncedVersion = syncedVersion
    self.syncedSeq = syncedSeq
  }

  /// The server doesn't have this version yet: never pushed, or changed since its last push.
  /// The next sync pushes it with `baseVersion = syncedVersion ?? 0`.
  public var isDirty: Bool { syncedVersion != version }
}

extension SealedRecord {
  /// A pulled record as it lands locally: byte-identical `sealed` (§9.1), the server's version
  /// and seq as its sync base -- clean.
  init(_ remote: RecordDTO) {
    self.init(
      id: remote.id, version: remote.version, schemaVersion: 1, sealed: remote.sealed,
      isDeleted: remote.isDeleted, updatedAt: remote.hlc.hlc, syncedVersion: remote.version,
      syncedSeq: remote.seq)
  }
}

// MARK: - GRDB

extension SealedRecord: FetchableRecord, PersistableRecord {
  public static let databaseTableName = "records"

  /// The HLC is split over three columns: `updated_at` (wall millis, since v1), `hlc_counter` and
  /// `hlc_device` (v2). The sync columns are outside the manifest MAC (§5.5): bookkeeping, not
  /// content.
  public init(row: Row) throws {
    id = UUID(fromRawData: row["uuid"])
    version = UInt64(bitPattern: row["version"])
    schemaVersion = 1  // M2 is always schema 1; the repository confirms against schema_version
    sealed = row["sealed"]
    isDeleted = (row["is_deleted"] as Int64) != 0
    updatedAt = HLC(
      wallMillis: UInt64(bitPattern: row["updated_at"]),
      counter: UInt32(truncatingIfNeeded: row["hlc_counter"] as Int64),
      deviceID: UUID(fromRawData: row["hlc_device"]))
    blindTitle = row["idx_title"]
    blindURL = row["idx_url"]
    syncedVersion = (row["synced_version"] as Int64?).map { UInt64(bitPattern: $0) }
    syncedSeq = (row["synced_seq"] as Int64?).map { UInt64(bitPattern: $0) }
  }

  public func encode(to container: inout PersistenceContainer) throws {
    container["uuid"] = id.rawData
    container["version"] = Int64(bitPattern: version)
    container["sealed"] = sealed
    container["is_deleted"] = isDeleted ? 1 : 0
    container["updated_at"] = Int64(bitPattern: updatedAt.wallMillis)
    container["hlc_counter"] = Int64(updatedAt.counter)
    container["hlc_device"] = updatedAt.deviceID.rawData
    container["idx_title"] = blindTitle
    container["idx_url"] = blindURL
    container["synced_version"] = syncedVersion.map { Int64(bitPattern: $0) }
    container["synced_seq"] = syncedSeq.map { Int64(bitPattern: $0) }
  }
}

// MARK: - UUID <-> 16 raw bytes

extension UUID {
  /// The 16 raw bytes, RFC 4122 order -- what a `records.uuid` BLOB holds (not
  /// GRDB's default 36-char string).
  var rawData: Data { withUnsafeBytes(of: uuid) { Data($0) } }

  /// Rebuild from a 16-byte BLOB; a wrong length yields the all-zero UUID rather
  /// than trapping (a corrupt row is a caller problem, surfaced elsewhere).
  init(fromRawData data: Data) {
    var bytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    if data.count == 16 {
      withUnsafeMutableBytes(of: &bytes) { $0.copyBytes(from: data) }
    }
    self = UUID(uuid: bytes)
  }
}
