import Foundation
import Testing

@testable import PassFortVault

/// `HTTPSyncAPI` against a stub `SyncTransport` (m5-sync.md 7.2; ADR-0011 decision 4): the
/// endpoint rule, what each call sends, and how every status maps to `SyncError`. It runs on every
/// platform; `URLSessionTransportTests` and `CurlTransportTests` cover the two real transports, and
/// the Phase 11 drill the real server.
@Suite struct HTTPSyncAPITests {

  // MARK: - Stub

  /// One canned reply, or a transport failure.
  struct Reply: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
    var error: SyncError?
  }

  /// Answers every request with its reply and keeps what was sent.
  final class Stub: SyncTransport {
    private let reply: Reply
    private let sent = Locked(initialState: [SyncHTTPRequest]())

    init(_ reply: Reply) {
      self.reply = reply
    }

    var captured: [SyncHTTPRequest] { sent.withLock { $0 } }

    func send(_ request: SyncHTTPRequest) async throws -> SyncHTTPResponse {
      sent.withLock { $0.append(request) }
      if let error = reply.error { throw error }
      return SyncHTTPResponse(status: reply.status, headers: reply.headers, body: reply.body)
    }
  }

  /// An API whose requests all land in a fresh stub.
  private func stubbed(_ reply: Reply, https: Bool = false) throws -> (HTTPSyncAPI, Stub) {
    let stub = Stub(reply)
    let endpoint =
      https
      ? URL(string: "https://sync.test/api/v1")!
      : URL(string: "http://localhost:7071/api/v1")!
    let pins = try PinSet(base64: ["M1AWPj3AZEniRAxIO4lxAIEtRyVX2LOoj7MHpuzGpDU="])
    return (try HTTPSyncAPI(endpoint: endpoint, pins: pins, transport: stub), stub)
  }

  private func fixture(_ name: String) throws -> Data { try SyncDTOTests.fixture(name) }

  private let vaultID = UUID(uuidString: "6F1C2B3A-4D5E-4F60-8A7B-9C0D1E2F3A4B")!
  private let device = DeviceDTO(id: UUID(), name: "test", platform: .cli)

  @Test func headerLookupIgnoresCase() throws {
    // Foundation on Linux stores header names capitalized (`X-Passfort-Token`).
    let sent = SyncHTTPRequest(
      method: "GET", url: try #require(URL(string: "http://localhost/")),
      headers: ["X-Passfort-Token": "tok"], body: nil)
    #expect(sent.header("X-PassFort-Token") == "tok")
    #expect(sent.header("x-passfort-token") == "tok")
    #expect(sent.header("Authorization") == nil)
    let response = SyncHTTPResponse(status: 503, headers: ["retry-after": "4"], body: Data())
    #expect(response.header("Retry-After") == "4")
  }

  // MARK: - The endpoint rule (A.4)

  @Test(arguments: [
    "http://example.com/api/v1", "http://10.0.0.5:7071/api/v1", "http://sync.test/api/v1",
    "ftp://localhost/api/v1", "ws://127.0.0.1/api/v1",
  ])
  func refusesAnythingButHTTPSOffLoopback(_ endpoint: String) {
    let pins = PinSet(hashes: [Data(count: 32)])
    #expect(throws: SyncError.insecureEndpoint) {
      try HTTPSyncAPI(endpoint: URL(string: endpoint)!, pins: pins)
    }
  }

  @Test(arguments: [
    "http://localhost:7071/api/v1", "http://127.0.0.1:7071/api/v1", "http://[::1]:7071/api/v1",
    "https://localhost/api/v1",
  ])
  func acceptsLoopbackWithoutPins(_ endpoint: String) throws {
    _ = try HTTPSyncAPI(endpoint: URL(string: endpoint)!, pins: .none)
  }

  @Test func refusesHTTPSWithoutPinsButAcceptsItWithThem() throws {
    let endpoint = URL(string: "https://passfort.azurestaticapps.net/api/v1")!
    #expect(throws: SyncError.noPins) { try HTTPSyncAPI(endpoint: endpoint, pins: .none) }
    _ = try HTTPSyncAPI(endpoint: endpoint, pins: PinSet(hashes: [Data(count: 32)]))
  }

  // MARK: - What each call sends

  @Test func createVaultSendsTheEnrollSecretAndTheBody() async throws {
    let (api, stub) = try stubbed(
      Reply(status: 201, body: try fixture("create-vault.response.json")))
    let request = try SyncCoding.decoder.decode(
      CreateVaultRequest.self, from: try fixture("create-vault.request.json"))

    let response = try await api.createVault(request, enrollSecret: "enroll-me")
    #expect(response == CreateVaultResponse(seq: 0, headerVersion: 1))

    let sent = try #require(stub.captured.first)
    #expect(sent.method == "POST")
    #expect(sent.url.path().hasSuffix("/api/v1/vaults"))
    #expect(sent.header("X-PassFort-Enroll") == "enroll-me")
    #expect(sent.header("Content-Type") == "application/json")
    #expect(sent.header("X-PassFort-Token") == nil)
    #expect(sent.header("Authorization") == nil)
    let body = try JSONSerialization.jsonObject(with: try #require(sent.body)) as? NSDictionary
    let expected = try JSONSerialization.jsonObject(with: try fixture("create-vault.request.json"))
    #expect(body == expected as? NSDictionary)
  }

  @Test func authenticatedCallsCarryTheSessionTokenAndLowerCaseIDs() async throws {
    let (api, stub) = try stubbed(Reply(body: try fixture("changes.response.json")))
    let page = try await api.changes(vaultID: vaultID, since: 40, limit: 500, token: "tok")
    #expect(page.records.count == 2)

    let sent = try #require(stub.captured.first)
    #expect(sent.method == "GET")
    #expect(sent.body == nil && sent.header("Content-Type") == nil, "a GET sends no body")
    #expect(sent.header("X-PassFort-Token") == "tok")
    #expect(sent.header("Authorization") == nil)
    #expect(sent.url.path().hasSuffix("/vaults/6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b/changes"))
    let query = URLComponents(url: sent.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(
      Set(query) == [
        URLQueryItem(name: "since", value: "40"), URLQueryItem(name: "limit", value: "500"),
      ])
  }

  @Test func everyEndpointHitsItsRoute() async throws {
    let v = "vaults/6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    let other = UUID(uuidString: "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D")!

    func check(
      _ reply: Reply, _ method: String, _ suffix: String, _ call: (HTTPSyncAPI) async throws -> Void
    ) async throws {
      let (api, stub) = try stubbed(reply)
      try await call(api)
      let sent = try #require(stub.captured.first)
      #expect(sent.method == method)
      #expect(sent.url.path().hasSuffix("/api/v1/\(suffix)"), "\(sent.url)")
    }

    try await check(Reply(body: try fixture("session.response.json")), "POST", "\(v)/session") {
      _ = try await $0.openSession(
        vaultID: vaultID, SessionRequest(authKey: Data(count: 32), device: device))
    }
    try await check(Reply(body: try fixture("header.response.json")), "GET", "\(v)/header") {
      _ = try await $0.header(vaultID: vaultID)
    }
    try await check(Reply(body: try fixture("put-header.response.json")), "PUT", "\(v)/header") {
      let version = try await $0.putHeader(
        vaultID: vaultID, header: Data(count: 133), base: 2, token: "t")
      #expect(version == 3)
    }
    try await check(Reply(body: try fixture("push.response.json")), "POST", "\(v)/changes") {
      _ = try await $0.push(vaultID: vaultID, [], token: "t")
    }
    try await check(Reply(body: try fixture("devices.response.json")), "GET", "\(v)/devices") {
      let devices = try await $0.devices(vaultID: vaultID, token: "t")
      #expect(devices.count == 2)
    }
    try await check(
      Reply(status: 204), "DELETE", "\(v)/devices/a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"
    ) {
      try await $0.removeDevice(vaultID: vaultID, deviceID: other, token: "t")
    }
    try await check(Reply(status: 204), "DELETE", v) {
      try await $0.deleteVault(vaultID: vaultID, token: "t")
    }
  }

  @Test func httpsEndpointsWorkTheSameWay() async throws {
    let (api, stub) = try stubbed(Reply(body: try fixture("header.response.json")), https: true)
    _ = try await api.header(vaultID: vaultID)
    #expect(stub.captured.first?.url.scheme == "https")
  }

  // MARK: - Status mapping

  @Test(arguments: [
    (400, SyncError.badRequest), (401, .unauthorized), (403, .forbidden), (404, .notFound),
    (410, .resyncRequired), (413, .tooLarge), (302, .redirectRefused), (307, .redirectRefused),
    (500, .server(status: 500, retryAfter: nil)),
  ])
  func statusesMapToSyncErrors(_ status: Int, _ expected: SyncError) async throws {
    let (api, _) = try stubbed(Reply(status: status, body: try fixture("error.json")))
    await #expect(throws: expected) { _ = try await api.header(vaultID: vaultID) }
  }

  @Test func retryAfterIsCarriedOn429And503() async throws {
    let (limited, _) = try stubbed(Reply(status: 429, headers: ["Retry-After": "30"]))
    await #expect(throws: SyncError.rateLimited(retryAfter: 30)) {
      _ = try await limited.openSession(
        vaultID: vaultID, SessionRequest(authKey: Data(count: 32), device: device))
    }
    let (busy, _) = try stubbed(Reply(status: 503, headers: ["Retry-After": "1"]))
    await #expect(throws: SyncError.server(status: 503, retryAfter: 1)) {
      _ = try await busy.push(vaultID: vaultID, [], token: "t")
    }
  }

  @Test func a409MeansWhatItsEndpointSays() async throws {
    let (create, _) = try stubbed(Reply(status: 409, body: try fixture("error.json")))
    let request = try SyncCoding.decoder.decode(
      CreateVaultRequest.self, from: try fixture("create-vault.request.json"))
    await #expect(throws: SyncError.vaultExists) {
      _ = try await create.createVault(request, enrollSecret: "x")
    }

    let (push, _) = try stubbed(Reply(status: 409, body: try fixture("push.conflict.json")))
    let stale = UUID(uuidString: "66666666-7777-4888-9999-AAAAAAAAAAAA")!
    await #expect(throws: SyncError.conflicts([ConflictDTO(id: stale, serverVersion: 5)])) {
      _ = try await push.push(vaultID: vaultID, [], token: "t")
    }

    let (header, _) = try stubbed(Reply(status: 409, body: try fixture("put-header.conflict.json")))
    await #expect(throws: SyncError.headerConflict(headerVersion: 3)) {
      _ = try await header.putHeader(
        vaultID: vaultID, header: Data(count: 133), base: 2, token: "t")
    }
  }

  @Test func anUndecodableSuccessIsInvalidResponse() async throws {
    let (api, _) = try stubbed(Reply(body: Data(#"{"surprise":true}"#.utf8)))
    await #expect(throws: SyncError.invalidResponse) { _ = try await api.header(vaultID: vaultID) }
  }

  // MARK: - Transport failures

  /// The transports map their own failures (URLError, libcurl); HTTPSyncAPI passes them on.
  @Test(arguments: [SyncError.offline, .pinningFailed, .invalidResponse])
  func transportFailuresPassThroughUnchanged(_ error: SyncError) async throws {
    let (api, _) = try stubbed(Reply(error: error))
    await #expect(throws: error) { _ = try await api.header(vaultID: vaultID) }
  }
}
