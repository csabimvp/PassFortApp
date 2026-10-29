import Foundation

/// `SyncAPI` over HTTPS (`m5-sync.md` 7.2): pinned TLS, a 15 s request timeout, no cache, no
/// cookies, and nothing logged -- bodies carry `k_auth`, tokens and sealed blobs. Stateless: the
/// engine passes the token in. Every failure is a `SyncError`. The bytes go through a
/// `SyncTransport`: `URLSession` with `PinnedTransport` on Apple platforms, libcurl on Linux
/// (ADR-0011).
///
/// **HTTPS only, in code** (A.4): `init` refuses an endpoint that isn't `https`, unless it is
/// plain `http` to a loopback host (the local `npm run dev` loop). App Transport Security would
/// stop plain HTTP in the app anyway, but it doesn't apply to the CLI, and this type serves both.
/// Redirects are refused by both transports, so a `3xx` can't downgrade the scheme or move the
/// request elsewhere.
public final class HTTPSyncAPI: SyncAPI {
  public static let requestTimeout: TimeInterval = 15

  private let endpoint: URL
  private let transport: any SyncTransport

  /// - Parameters:
  ///   - endpoint: the API root, e.g. `https://<site>.azurestaticapps.net/api/v1`.
  ///   - pins: SPKI pins for the server's chain; may be empty only for a loopback endpoint.
  /// - Throws: `SyncError.insecureEndpoint`, `SyncError.noPins` -- before any request exists.
  public convenience init(endpoint: URL, pins: PinSet) throws {
    try Self.checkEndpoint(endpoint, pins: pins)
    #if canImport(Security)
      try self.init(endpoint: endpoint, pins: pins, transport: URLSessionTransport(pins: pins))
    #elseif os(Linux)
      try self.init(endpoint: endpoint, pins: pins, transport: CurlTransport(pins: pins))
    #else
      #error("no pinned HTTPS transport for this platform (ADR-0011)")
    #endif
  }

  /// The designated initializer; tests pass a stub transport.
  init(endpoint: URL, pins: PinSet, transport: any SyncTransport) throws {
    try Self.checkEndpoint(endpoint, pins: pins)
    self.endpoint = endpoint
    self.transport = transport
  }

  /// `https` anywhere (with pins), or `http` / `https` to this machine. Nothing else.
  static func checkEndpoint(_ endpoint: URL, pins: PinSet) throws {
    let scheme = endpoint.scheme?.lowercased()
    if PinSet.isLoopback(host: endpoint.host()) {
      guard scheme == "http" || scheme == "https" else { throw SyncError.insecureEndpoint }
      return
    }
    guard scheme == "https" else { throw SyncError.insecureEndpoint }
    guard !pins.isEmpty else { throw SyncError.noPins }
  }

  // MARK: - SyncAPI

  public func createVault(_ request: CreateVaultRequest, enrollSecret: String) async throws
    -> CreateVaultResponse
  {
    try await call(
      "POST", "vaults", body: request, headers: ["X-PassFort-Enroll": enrollSecret],
      conflict: { _ in .vaultExists })
  }

  public func openSession(vaultID: UUID, _ request: SessionRequest) async throws
    -> SessionResponse
  {
    try await call("POST", "vaults/\(vaultID.wire)/session", body: request)
  }

  public func header(vaultID: UUID) async throws -> HeaderResponse {
    try await call("GET", "vaults/\(vaultID.wire)/header")
  }

  public func putHeader(vaultID: UUID, header: Data, base: UInt64, token: String) async throws
    -> UInt64
  {
    let response: PutHeaderResponse = try await call(
      "PUT", "vaults/\(vaultID.wire)/header",
      body: PutHeaderRequest(header: header, baseHeaderVersion: base), token: token,
      conflict: { data in
        (try? SyncCoding.decoder.decode(HeaderConflictResponse.self, from: data))
          .map { .headerConflict(headerVersion: $0.headerVersion) }
      })
    return response.headerVersion
  }

  public func changes(vaultID: UUID, since: UInt64, limit: Int, token: String) async throws
    -> ChangesResponse
  {
    try await call(
      "GET", "vaults/\(vaultID.wire)/changes",
      query: [
        URLQueryItem(name: "since", value: String(since)),
        URLQueryItem(name: "limit", value: String(limit)),
      ],
      token: token)
  }

  public func push(vaultID: UUID, _ records: [PushDTO], token: String) async throws
    -> PushResponse
  {
    try await call(
      "POST", "vaults/\(vaultID.wire)/changes", body: PushRequest(records: records), token: token,
      conflict: { data in
        (try? SyncCoding.decoder.decode(ConflictResponse.self, from: data))
          .map { .conflicts($0.conflicts) }
      })
  }

  public func devices(vaultID: UUID, token: String) async throws -> [DeviceInfoDTO] {
    let response: DevicesResponse = try await call(
      "GET", "vaults/\(vaultID.wire)/devices", token: token)
    return response.devices
  }

  public func removeDevice(vaultID: UUID, deviceID: UUID, token: String) async throws {
    try await callExpectingNoContent(
      "DELETE", "vaults/\(vaultID.wire)/devices/\(deviceID.wire)", token: token)
  }

  public func deleteVault(vaultID: UUID, token: String) async throws {
    try await callExpectingNoContent("DELETE", "vaults/\(vaultID.wire)", token: token)
  }

  // MARK: - Transport

  /// Maps a `409` body to the error it means for this endpoint; `nil` for "not one I know".
  private typealias ConflictMapper = @Sendable (Data) -> SyncError?

  private func call<Response: Decodable>(
    _ method: String, _ path: String, query: [URLQueryItem] = [],
    body: (some Encodable)? = nil as Never?, token: String? = nil,
    headers: [String: String] = [:], conflict: ConflictMapper? = nil
  ) async throws -> Response {
    let data = try await send(
      method, path, query: query, body: body, token: token, headers: headers, conflict: conflict)
    do {
      return try SyncCoding.decoder.decode(Response.self, from: data)
    } catch {
      throw SyncError.invalidResponse
    }
  }

  private func callExpectingNoContent(_ method: String, _ path: String, token: String)
    async throws
  {
    _ = try await send(
      method, path, query: [], body: nil as Never?, token: token, headers: [:], conflict: nil)
  }

  /// One request; returns a `2xx` body or throws the mapped `SyncError`.
  private func send(
    _ method: String, _ path: String, query: [URLQueryItem], body: (some Encodable)?,
    token: String?, headers: [String: String], conflict: ConflictMapper?
  ) async throws -> Data {
    var url = endpoint.appending(path: path)
    if !query.isEmpty { url.append(queryItems: query) }
    var request = SyncHTTPRequest(
      method: method, url: url, headers: ["Accept": "application/json"], body: nil)
    if let body {
      request.body = try SyncCoding.encoder.encode(body)
      request.headers["Content-Type"] = "application/json"
    }
    // Not `Authorization`: Static Web Apps replaces that header before the API sees it.
    if let token { request.headers["X-PassFort-Token"] = token }
    for (name, value) in headers { request.headers[name] = value }

    let response = try await transport.send(request)
    switch response.status {
    case 200..<300: return response.body
    case 409: throw conflict?(response.body) ?? SyncError.server(status: 409, retryAfter: nil)
    default: throw Self.error(for: response)
    }
  }

  // MARK: - Error mapping

  static func error(for response: SyncHTTPResponse) -> SyncError {
    let retryAfter = response.header("Retry-After").flatMap(TimeInterval.init)
    switch response.status {
    case 300..<400: return .redirectRefused
    case 400: return .badRequest
    case 401: return .unauthorized
    case 403: return .forbidden
    case 404: return .notFound
    case 410: return .resyncRequired
    case 413: return .tooLarge
    case 429: return .rateLimited(retryAfter: retryAfter ?? 1)
    default: return .server(status: response.status, retryAfter: retryAfter)
    }
  }
}

extension UUID {
  /// The contract's `Uuid`: lower-case.
  fileprivate var wire: String { uuidString.lowercased() }
}
