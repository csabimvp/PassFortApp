import Foundation

// The wire types of the sync API -- `Codable` mirrors of `SyncAPI/openapi.yaml`, one for one, by
// hand (`m5-sync.md` 7.1). They are the wire boundary: `SealedRecord` itself is never `Codable`.
// `SyncAPI/fixtures/dto/` holds one JSON file per message; `SyncDTOTests` checks these types against
// it, and the server's test suite checks its validators against the same files.
//
// Encoding follows the contract: `Data` as standard padded base64 (the `JSONEncoder` default),
// UUIDs lower-case (the `JSONEncoder` default is upper-case, which the server refuses), dates
// RFC 3339. Use `SyncCoding` -- not a bare `JSONEncoder` / `JSONDecoder`.

// MARK: - Coding

public enum SyncCoding {
  public static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return encoder
  }

  /// Dates with or without fractional seconds: the server writes `toISOString()`
  /// (`2026-10-23T12:00:00.000Z`), which the stock `.iso8601` strategy rejects.
  public static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let text = try decoder.singleValueContainer().decode(String.self)
      for style in [
        Date.ISO8601FormatStyle(includingFractionalSeconds: true), Date.ISO8601FormatStyle(),
      ] {
        if let date = try? Date(text, strategy: style) { return date }
      }
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "not an RFC 3339 date"))
    }
    return decoder
  }
}

extension KeyedEncodingContainer {
  /// The contract's `Uuid`: lower-case.
  fileprivate mutating func encodeUUID(_ uuid: UUID, forKey key: Key) throws {
    try encode(uuid.uuidString.lowercased(), forKey: key)
  }
}

// MARK: - Shared objects

public enum DevicePlatform: String, Codable, Sendable {
  case macos, ios, cli, web
}

/// `Device`: who is creating a vault or opening a session.
public struct DeviceDTO: Codable, Sendable, Equatable {
  public var id: UUID
  public var name: String
  public var platform: DevicePlatform

  public init(id: UUID, name: String, platform: DevicePlatform) {
    self.id = id
    self.name = name
    self.platform = platform
  }

  public init(_ identity: DeviceIdentity, platform: DevicePlatform) {
    self.init(id: identity.id, name: identity.name, platform: platform)
  }

  enum CodingKeys: String, CodingKey { case id, name, platform }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeUUID(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(platform, forKey: .platform)
  }
}

/// `DeviceInfo`: one row of `GET /devices`.
public struct DeviceInfoDTO: Codable, Sendable, Equatable {
  public var id: UUID
  public var name: String
  public var platform: DevicePlatform
  public var lastSeq: UInt64
  public var lastSeenAt: Date
}

/// `Hlc`.
public struct HLCDTO: Codable, Sendable, Equatable {
  public var wallMillis: UInt64
  public var counter: UInt32
  public var deviceId: UUID

  public init(_ hlc: HLC) {
    wallMillis = hlc.wallMillis
    counter = hlc.counter
    deviceId = hlc.deviceID
  }

  public var hlc: HLC { HLC(wallMillis: wallMillis, counter: counter, deviceID: deviceId) }

  enum CodingKeys: String, CodingKey { case wallMillis, counter, deviceId }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(wallMillis, forKey: .wallMillis)
    try container.encode(counter, forKey: .counter)
    try container.encodeUUID(deviceId, forKey: .deviceId)
  }
}

/// `Record`: one record as pulled.
public struct RecordDTO: Codable, Sendable, Equatable {
  public var id: UUID
  public var version: UInt64
  public var hlc: HLCDTO
  public var sealed: Data
  public var isDeleted: Bool
  public var seq: UInt64
  /// The device that pushed this version -- from its token, not from anything it sent.
  public var writer: UUID
}

/// `Push`: one element of a push batch.
public struct PushDTO: Codable, Sendable, Equatable {
  public var id: UUID
  /// The server version this edit was made on; 0 = the record must not exist there yet.
  public var baseVersion: UInt64
  public var version: UInt64
  public var hlc: HLCDTO
  public var sealed: Data
  public var isDeleted: Bool

  public init(
    id: UUID, baseVersion: UInt64, version: UInt64, hlc: HLCDTO, sealed: Data, isDeleted: Bool
  ) {
    self.id = id
    self.baseVersion = baseVersion
    self.version = version
    self.hlc = hlc
    self.sealed = sealed
    self.isDeleted = isDeleted
  }

  /// A dirty row as pushed: based on the version the server last confirmed (A.5).
  public init(_ record: SealedRecord) {
    self.init(
      id: record.id, baseVersion: record.syncedVersion ?? 0, version: record.version,
      hlc: HLCDTO(record.updatedAt), sealed: record.sealed, isDeleted: record.isDeleted)
  }

  enum CodingKeys: String, CodingKey { case id, baseVersion, version, hlc, sealed, isDeleted }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeUUID(id, forKey: .id)
    try container.encode(baseVersion, forKey: .baseVersion)
    try container.encode(version, forKey: .version)
    try container.encode(hlc, forKey: .hlc)
    try container.encode(sealed, forKey: .sealed)
    try container.encode(isDeleted, forKey: .isDeleted)
  }
}

/// `Error`: every error body. `error` stays a string so a code added to the contract later
/// still decodes.
public struct ErrorDTO: Codable, Sendable, Equatable {
  public var error: String
  public var message: String
}

// MARK: - Requests

/// `CreateVaultRequest` -- `POST /vaults`.
public struct CreateVaultRequest: Codable, Sendable, Equatable {
  public var vaultId: UUID
  public var header: Data
  /// `k_auth`, exactly 32 bytes (ADR-0009).
  public var authKey: Data
  public var device: DeviceDTO

  public init(vaultId: UUID, header: Data, authKey: Data, device: DeviceDTO) {
    self.vaultId = vaultId
    self.header = header
    self.authKey = authKey
    self.device = device
  }

  enum CodingKeys: String, CodingKey { case vaultId, header, authKey, device }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeUUID(vaultId, forKey: .vaultId)
    try container.encode(header, forKey: .header)
    try container.encode(authKey, forKey: .authKey)
    try container.encode(device, forKey: .device)
  }
}

/// `OpenSessionRequest` -- `POST /vaults/{id}/session`.
public struct SessionRequest: Codable, Sendable, Equatable {
  public var authKey: Data
  public var device: DeviceDTO

  public init(authKey: Data, device: DeviceDTO) {
    self.authKey = authKey
    self.device = device
  }
}

/// `PutHeaderRequest` -- `PUT /vaults/{id}/header`.
public struct PutHeaderRequest: Codable, Sendable, Equatable {
  public var header: Data
  public var baseHeaderVersion: UInt64
}

/// `PushRequest` -- `POST /vaults/{id}/changes`.
public struct PushRequest: Codable, Sendable, Equatable {
  public var records: [PushDTO]
}

// MARK: - Responses

/// `CreateVaultResponse`.
public struct CreateVaultResponse: Codable, Sendable, Equatable {
  public var seq: UInt64
  public var headerVersion: UInt64
}

/// `OpenSessionResponse`.
public struct SessionResponse: Codable, Sendable, Equatable {
  /// A 15-minute bearer token. Memory only -- never logged, never stored (ADR-0009).
  public var token: String
  public var expiresAt: Date
  public var seq: UInt64
  public var headerVersion: UInt64
  public var purgedThroughSeq: UInt64
}

/// `HeaderResponse` -- `GET /vaults/{id}/header`.
public struct HeaderResponse: Codable, Sendable, Equatable {
  public var header: Data
  public var headerVersion: UInt64
}

/// `PutHeaderResponse`.
public struct PutHeaderResponse: Codable, Sendable, Equatable {
  public var headerVersion: UInt64
}

/// `HeaderConflict` -- the `409` of a header PUT from a stale base.
public struct HeaderConflictResponse: Codable, Sendable, Equatable {
  public var error: String
  public var message: String
  public var headerVersion: UInt64
}

/// `ChangesResponse` -- one page of a pull.
public struct ChangesResponse: Codable, Sendable, Equatable {
  public var records: [RecordDTO]
  /// The server's high-water mark, even when `records` is empty.
  public var seq: UInt64
  public var hasMore: Bool
  public var headerVersion: UInt64
  public var purgedThroughSeq: UInt64
}

/// One record a push stored.
public struct AppliedDTO: Codable, Sendable, Equatable {
  public var id: UUID
  public var version: UInt64
  public var seq: UInt64

  public var pushed: PushedRecord { PushedRecord(id: id, version: version, seq: seq) }
}

/// `PushResponse`.
public struct PushResponse: Codable, Sendable, Equatable {
  public var applied: [AppliedDTO]
  public var seq: UInt64
}

/// One stale record in a refused push. `serverVersion` 0 = the server doesn't have it.
public struct ConflictDTO: Codable, Sendable, Equatable {
  public var id: UUID
  public var serverVersion: UInt64

  public init(id: UUID, serverVersion: UInt64) {
    self.id = id
    self.serverVersion = serverVersion
  }
}

/// `PushConflict` -- the `409` of a push; nothing was written.
public struct ConflictResponse: Codable, Sendable, Equatable {
  public var error: String
  public var message: String
  public var conflicts: [ConflictDTO]
}

/// `DevicesResponse`.
public struct DevicesResponse: Codable, Sendable, Equatable {
  public var devices: [DeviceInfoDTO]
}
