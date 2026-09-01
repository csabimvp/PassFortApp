import Foundation

/// The escape hatch (§1.3, §7.6): every secret, decrypted, as readable JSON that a
/// person or a five-line import script can consume. The format is ours, so a
/// tested way out of it is mandatory, not optional.
public struct PlaintextExport: Codable, Sendable, Equatable {
  public var schemaVersion: UInt16
  public var exportedAt: Date
  public var vaultUUID: UUID
  public var accounts: [ExportedAccount]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case exportedAt = "exported_at"
    case vaultUUID = "vault_uuid"
    case accounts
  }

  public init(
    schemaVersion: UInt16, exportedAt: Date, vaultUUID: UUID, accounts: [ExportedAccount]
  ) {
    self.schemaVersion = schemaVersion
    self.exportedAt = exportedAt
    self.vaultUUID = vaultUUID
    self.accounts = accounts
  }

  /// Pretty-printed, snake_case, sorted keys, ISO-8601 dates. This is **plaintext
  /// secrets** -- the caller writes it `0600` and tells the user so.
  public func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(self)
  }
}

/// One account in an export: the envelope identity fields flattened alongside the
/// fully-decrypted payload. Tombstones are included (with `is_deleted: true`) so an
/// export is a complete snapshot.
public struct ExportedAccount: Codable, Sendable, Equatable {
  public var id: UUID
  public var version: UInt64
  public var updatedAt: Date
  public var isDeleted: Bool
  public var payload: AccountPayload

  enum CodingKeys: String, CodingKey {
    case id
    case version
    case updatedAt = "updated_at"
    case isDeleted = "is_deleted"
    case payload
  }

  public init(
    id: UUID, version: UInt64, updatedAt: Date, isDeleted: Bool, payload: AccountPayload
  ) {
    self.id = id
    self.version = version
    self.updatedAt = updatedAt
    self.isDeleted = isDeleted
    self.payload = payload
  }
}

/// The typed confirmation `exportPlaintext` demands (§5.6): a plaintext export
/// cannot happen by accident. The CLI / UI reads the exact phrase back from the
/// user and constructs this; nothing else can.
public struct ExportConfirmation: Sendable {
  public static let phrase = "EXPORT PLAINTEXT"

  public init(phrase: String) throws {
    guard phrase == Self.phrase else { throw VaultError.exportNotConfirmed }
  }
}
