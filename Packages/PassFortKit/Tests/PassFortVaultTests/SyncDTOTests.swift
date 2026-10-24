import Foundation
import Testing

@testable import PassFortVault

/// The Swift DTOs against the shared contract fixtures (`SyncAPI/fixtures/dto`, m5-sync.md 7.1).
/// The server's suite runs its validators over the same request files, so a request that passes
/// here is one the server accepts.
@Suite struct SyncDTOTests {

  /// Tests/PassFortVaultTests/ -> the repository root -> SyncAPI/fixtures/dto.
  static let fixturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "SyncAPI/fixtures/dto")

  static func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixturesDir.appending(path: name))
  }

  private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try SyncCoding.decoder.decode(type, from: try Self.fixture(name))
  }

  /// Decode the fixture, re-encode it, and compare as JSON values: every field present, named
  /// and encoded (lower-case UUIDs, base64) exactly as the file has it, and nothing extra.
  private func expectRoundTrip<T: Codable>(_ type: T.Type, _ name: String) throws {
    let original = try Self.fixture(name)
    let reencoded = try SyncCoding.encoder.encode(try SyncCoding.decoder.decode(type, from: original))
    let expected = try JSONSerialization.jsonObject(with: original) as? NSDictionary
    let actual = try JSONSerialization.jsonObject(with: reencoded) as? NSDictionary
    #expect(expected != nil && actual == expected, "\(name)")
  }

  // MARK: - Requests: encoded exactly as the fixtures

  @Test func requestsEncodeExactlyAsTheContractFixtures() throws {
    try expectRoundTrip(CreateVaultRequest.self, "create-vault.request.json")
    try expectRoundTrip(SessionRequest.self, "session.request.json")
    try expectRoundTrip(PutHeaderRequest.self, "put-header.request.json")
    try expectRoundTrip(PushRequest.self, "push.request.json")
  }

  @Test func uuidsGoOutLowerCase() throws {
    let device = DeviceDTO(
      id: UUID(uuidString: "0F1E2D3C-4B5A-4978-8796-A5B4C3D2E1F0") ?? UUID(), name: "x",
      platform: .cli)
    let json = String(decoding: try SyncCoding.encoder.encode(device), as: UTF8.self)
    #expect(json.contains("0f1e2d3c-4b5a-4978-8796-a5b4c3d2e1f0"))
    #expect(!json.contains("0F1E"))
  }

  @Test func aDirtyRowPushesFromItsSyncedVersion() {
    let hlc = HLC(wallMillis: 5, counter: 1, deviceID: UUID())
    var record = SealedRecord(
      id: UUID(), version: 4, schemaVersion: 1, sealed: Data(count: 296), isDeleted: true,
      updatedAt: hlc, syncedVersion: 3, syncedSeq: 9)
    var push = PushDTO(record)
    #expect(push.baseVersion == 3)
    #expect(push.version == 4)
    #expect(push.isDeleted)
    #expect(push.hlc.hlc == hlc)

    record.syncedVersion = nil  // never on the server
    push = PushDTO(record)
    #expect(push.baseVersion == 0)
  }

  // MARK: - Responses: decoded from the fixtures

  @Test func responsesDecodeFromTheContractFixtures() throws {
    #expect(try decode(CreateVaultResponse.self, "create-vault.response.json").headerVersion == 1)

    let session = try decode(SessionResponse.self, "session.response.json")
    #expect(session.seq == 41)
    #expect(session.purgedThroughSeq == 7)
    // `toISOString()` format, with milliseconds.
    #expect(session.expiresAt == Date(timeIntervalSince1970: 1_792_757_700))

    #expect(try decode(HeaderResponse.self, "header.response.json").header.count == 133)
    #expect(try decode(PutHeaderResponse.self, "put-header.response.json").headerVersion == 3)
    #expect(
      try decode(HeaderConflictResponse.self, "put-header.conflict.json").headerVersion == 3)

    let changes = try decode(ChangesResponse.self, "changes.response.json")
    #expect(changes.records.map(\.seq) == [40, 41])
    #expect(changes.records.map(\.sealed.count) == [296, 552])
    #expect(changes.records[1].isDeleted)
    #expect(changes.records[1].hlc.counter == 2)
    #expect(!changes.hasMore)

    let push = try decode(PushResponse.self, "push.response.json")
    #expect(push.applied.map(\.pushed.seq) == [42, 43])
    let conflict = try decode(ConflictResponse.self, "push.conflict.json")
    #expect(conflict.conflicts.map(\.serverVersion) == [5])

    let devices = try decode(DevicesResponse.self, "devices.response.json").devices
    #expect(devices.map(\.platform) == [.macos, .cli])
    #expect(devices[1].lastSeenAt == Date(timeIntervalSince1970: 1_792_657_815.25))

    #expect(try decode(ErrorDTO.self, "error.json").error == "unauthorized")
  }

  @Test func datesDecodeWithAndWithoutFractionalSeconds() throws {
    struct Stamp: Decodable { let at: Date }
    let decoder = SyncCoding.decoder
    let withMillis = try decoder.decode(Stamp.self, from: Data(#"{"at":"2026-10-23T12:00:00.500Z"}"#.utf8))
    let without = try decoder.decode(Stamp.self, from: Data(#"{"at":"2026-10-23T12:00:00Z"}"#.utf8))
    #expect(withMillis.at.timeIntervalSince(without.at) == 0.5)
    #expect(throws: DecodingError.self) {
      try decoder.decode(Stamp.self, from: Data(#"{"at":"yesterday"}"#.utf8))
    }
  }
}
