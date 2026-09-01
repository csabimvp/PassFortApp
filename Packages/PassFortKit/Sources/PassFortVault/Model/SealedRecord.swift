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
  public var blindTitle: Data?  // idx_title -- keyed blind index, M5
  public var blindURL: Data?  // idx_url

  public init(
    id: UUID, version: UInt64, schemaVersion: UInt16, sealed: Data, isDeleted: Bool = false,
    updatedAt: HLC, blindTitle: Data? = nil, blindURL: Data? = nil
  ) {
    self.id = id
    self.version = version
    self.schemaVersion = schemaVersion
    self.sealed = sealed
    self.isDeleted = isDeleted
    self.updatedAt = updatedAt
    self.blindTitle = blindTitle
    self.blindURL = blindURL
  }
}

// MARK: - GRDB

extension SealedRecord: FetchableRecord, PersistableRecord {
  public static let databaseTableName = "records"

  /// For M2, `updated_at` stores only the HLC wall-clock millis (single device,
  /// counter always 0). M5 sync adds the counter + device_id in a schema bump.
  private static let m2Device = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

  public init(row: Row) throws {
    id = UUID(fromRawData: row["uuid"])
    version = UInt64(bitPattern: row["version"])
    schemaVersion = 1  // M2 is always schema 1; the repository confirms against schema_version
    sealed = row["sealed"]
    isDeleted = (row["is_deleted"] as Int64) != 0
    updatedAt = HLC(
      wallMillis: UInt64(bitPattern: row["updated_at"]), counter: 0, deviceID: Self.m2Device)
    blindTitle = row["idx_title"]
    blindURL = row["idx_url"]
  }

  public func encode(to container: inout PersistenceContainer) throws {
    container["uuid"] = id.rawData
    container["version"] = Int64(bitPattern: version)
    container["sealed"] = sealed
    container["is_deleted"] = isDeleted ? 1 : 0
    container["updated_at"] = Int64(bitPattern: updatedAt.wallMillis)
    container["idx_title"] = blindTitle
    container["idx_url"] = blindURL
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
