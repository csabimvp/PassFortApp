import Foundation
import Testing
import os

@testable import PassFortVault

/// `HTTPSyncAPI` against a `URLProtocol` stub (m5-sync.md 7.2): the endpoint rule, what each call
/// sends, and how every status and transport failure maps to `SyncError`. The real server is
/// exercised end to end by the Phase 11 drill.
@Suite struct HTTPSyncAPITests {

  // MARK: - Stub

  /// One canned reply, or a transport error.
  struct Reply: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
    var error: URLError?
  }

  struct Captured: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data
  }

  /// Routes by the first path segment, a per-test id, so suites running in parallel never see each
  /// other's requests.
  final class Stub: URLProtocol, @unchecked Sendable {
    private static let routes = OSAllocatedUnfairLock(
      initialState: [String: (reply: Reply, captured: [Captured])]())

    static func register(_ id: String, _ reply: Reply) {
      routes.withLock { $0[id] = (reply, []) }
    }

    static func captured(_ id: String) -> [Captured] {
      routes.withLock { $0[id]?.captured ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      guard let url = request.url else { return }
      let id = url.pathComponents.dropFirst().first ?? ""
      let body = request.httpBodyStream.map(Self.read) ?? request.httpBody ?? Data()
      let capture = Captured(
        method: request.httpMethod ?? "", url: url,
        headers: request.allHTTPHeaderFields ?? [:], body: body)
      guard
        let reply = Self.routes.withLock({ routes -> Reply? in
          routes[id]?.captured.append(capture)
          return routes[id]?.reply
        })
      else { return client?.urlProtocol(self, didFailWithError: URLError(.badURL)) ?? () }

      if let error = reply.error { return client?.urlProtocol(self, didFailWithError: error) ?? () }
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
      if let response {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      }
      client?.urlProtocol(self, didLoad: reply.body)
      client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
      stream.open()
      defer { stream.close() }
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
      }
      return data
    }
  }

  /// An API whose requests all land in the stub under a fresh id.
  private func stubbed(_ reply: Reply, https: Bool = false) throws -> (HTTPSyncAPI, String) {
    let id = UUID().uuidString
    Stub.register(id, reply)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Stub.self]
    let endpoint =
      https
      ? URL(string: "https://sync.test/\(id)/api/v1")!
      : URL(string: "http://localhost:7071/\(id)/api/v1")!
    let pins = try PinSet(base64: ["M1AWPj3AZEniRAxIO4lxAIEtRyVX2LOoj7MHpuzGpDU="])
    return (try HTTPSyncAPI(endpoint: endpoint, pins: pins, configuration: configuration), id)
  }

  private func fixture(_ name: String) throws -> Data { try SyncDTOTests.fixture(name) }

  private let vaultID = UUID(uuidString: "6F1C2B3A-4D5E-4F60-8A7B-9C0D1E2F3A4B")!
  private let device = DeviceDTO(id: UUID(), name: "test", platform: .cli)

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
    let (api, id) = try stubbed(Reply(status: 201, body: try fixture("create-vault.response.json")))
    let request = try SyncCoding.decoder.decode(
      CreateVaultRequest.self, from: try fixture("create-vault.request.json"))

    let response = try await api.createVault(request, enrollSecret: "enroll-me")
    #expect(response == CreateVaultResponse(seq: 0, headerVersion: 1))

    let sent = try #require(Stub.captured(id).first)
    #expect(sent.method == "POST")
    #expect(sent.url.path().hasSuffix("/api/v1/vaults"))
    #expect(sent.headers["X-PassFort-Enroll"] == "enroll-me")
    #expect(sent.headers["Content-Type"] == "application/json")
    #expect(sent.headers["Authorization"] == nil)
    let body = try JSONSerialization.jsonObject(with: sent.body) as? NSDictionary
    let expected = try JSONSerialization.jsonObject(with: try fixture("create-vault.request.json"))
    #expect(body == expected as? NSDictionary)
  }

  @Test func authenticatedCallsCarryTheBearerTokenAndLowerCaseIDs() async throws {
    let (api, id) = try stubbed(Reply(body: try fixture("changes.response.json")))
    let page = try await api.changes(vaultID: vaultID, since: 40, limit: 500, token: "tok")
    #expect(page.records.count == 2)

    let sent = try #require(Stub.captured(id).first)
    #expect(sent.method == "GET")
    #expect(sent.headers["Authorization"] == "Bearer tok")
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
      let (api, id) = try stubbed(reply)
      try await call(api)
      let sent = try #require(Stub.captured(id).first)
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
    let (api, id) = try stubbed(Reply(body: try fixture("header.response.json")), https: true)
    _ = try await api.header(vaultID: vaultID)
    #expect(Stub.captured(id).first?.url.scheme == "https")
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

  @Test(arguments: [
    (URLError.Code.notConnectedToInternet, SyncError.offline), (.timedOut, .offline),
    (.cannotFindHost, .offline), (.networkConnectionLost, .offline),
    (.serverCertificateUntrusted, .pinningFailed),
    (.serverCertificateHasUnknownRoot, .pinningFailed),
  ])
  func transportErrorsMapToOfflineOrPinning(_ code: URLError.Code, _ expected: SyncError)
    async throws
  {
    let (api, _) = try stubbed(Reply(error: URLError(code)))
    await #expect(throws: expected) { _ = try await api.header(vaultID: vaultID) }
  }

  @Test func theTransportRefusesEveryRedirect() async {
    let transport = PinnedTransport(pins: .none)
    let session = URLSession(configuration: .ephemeral)
    let task = session.dataTask(with: URL(string: "https://sync.test/a")!)
    let redirect = HTTPURLResponse(
      url: URL(string: "https://sync.test/a")!, statusCode: 302, httpVersion: nil,
      headerFields: ["Location": "http://evil.test/a"])!
    let followed = await withCheckedContinuation { continuation in
      transport.urlSession(
        session, task: task, willPerformHTTPRedirection: redirect,
        newRequest: URLRequest(url: URL(string: "http://evil.test/a")!)
      ) { continuation.resume(returning: $0) }
    }
    #expect(followed == nil)
    session.invalidateAndCancel()
  }
}
