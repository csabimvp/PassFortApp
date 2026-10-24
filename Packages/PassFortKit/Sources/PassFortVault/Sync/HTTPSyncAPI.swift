import Foundation

/// `SyncAPI` over `URLSession` (`m5-sync.md` 7.2): pinned TLS, a 15 s request timeout, no cache,
/// no cookies, and nothing logged -- bodies carry `k_auth`, tokens and sealed blobs. Stateless:
/// the engine passes the token in. Every failure is a `SyncError`.
///
/// **HTTPS only, in code** (A.4): `init` refuses an endpoint that isn't `https`, unless it is
/// plain `http` to a loopback host (the local `npm run dev` loop). App Transport Security would
/// stop plain HTTP in the app anyway, but it doesn't apply to the CLI, and this type serves both.
/// Redirects are refused (`PinnedTransport`), so a `3xx` can't downgrade the scheme or move the
/// request elsewhere.
public final class HTTPSyncAPI: SyncAPI {
  public static let requestTimeout: TimeInterval = 15

  private let endpoint: URL
  private let session: URLSession
  private let transport: PinnedTransport

  /// - Parameters:
  ///   - endpoint: the API root, e.g. `https://<site>.azurestaticapps.net/api/v1`.
  ///   - pins: SPKI pins for the server's chain; may be empty only for a loopback endpoint.
  /// - Throws: `SyncError.insecureEndpoint`, `SyncError.noPins` -- before any request exists.
  public convenience init(endpoint: URL, pins: PinSet) throws {
    try self.init(endpoint: endpoint, pins: pins, configuration: .ephemeral)
  }

  /// The designated initializer; tests pass a configuration with stub `protocolClasses`.
  init(endpoint: URL, pins: PinSet, configuration: URLSessionConfiguration) throws {
    try Self.checkEndpoint(endpoint, pins: pins)
    self.endpoint = endpoint
    transport = PinnedTransport(pins: pins)

    configuration.timeoutIntervalForRequest = Self.requestTimeout
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.tlsMinimumSupportedProtocolVersion = .TLSv13  // §9.4
    session = URLSession(configuration: configuration, delegate: transport, delegateQueue: nil)
  }

  deinit {
    // The session holds its delegate strongly until invalidated.
    session.finishTasksAndInvalidate()
  }

  /// `https` anywhere (with pins), or `http` / `https` to this machine. Nothing else.
  static func checkEndpoint(_ endpoint: URL, pins: PinSet) throws {
    let scheme = endpoint.scheme?.lowercased()
    if PinnedTransport.isLoopback(host: endpoint.host()) {
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
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpBody = try SyncCoding.encoder.encode(body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    // Not `Authorization`: Static Web Apps replaces that header before the API sees it.
    if let token { request.setValue(token, forHTTPHeaderField: "X-PassFort-Token") }
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

    let (data, response) = try await perform(request)
    switch response.statusCode {
    case 200..<300: return data
    case 409: throw conflict?(data) ?? SyncError.server(status: 409, retryAfter: nil)
    default: throw Self.error(for: response)
    }
  }

  /// `dataTask` rather than `data(for:)`: the task's identifier is what tells a pinning failure
  /// apart from any other cancellation.
  private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let box = TaskBox()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let task = session.dataTask(with: request) { [transport] data, response, error in
          if let error {
            continuation.resume(
              throwing: Self.error(for: error, pinFailed: transport.takePinFailure(box.identifier)))
          } else if let response = response as? HTTPURLResponse {
            continuation.resume(returning: (data ?? Data(), response))
          } else {
            continuation.resume(throwing: SyncError.invalidResponse)
          }
        }
        box.task = task
        task.resume()
      }
    } onCancel: {
      box.task?.cancel()
    }
  }

  // MARK: - Error mapping

  static func error(for response: HTTPURLResponse) -> SyncError {
    let retryAfter = (response.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
    switch response.statusCode {
    case 300..<400: return .redirectRefused
    case 400: return .badRequest
    case 401: return .unauthorized
    case 403: return .forbidden
    case 404: return .notFound
    case 410: return .resyncRequired
    case 413: return .tooLarge
    case 429: return .rateLimited(retryAfter: retryAfter ?? 1)
    default: return .server(status: response.statusCode, retryAfter: retryAfter)
    }
  }

  static func error(for error: any Error, pinFailed: Bool) -> any Error {
    if pinFailed { return SyncError.pinningFailed }
    guard let urlError = error as? URLError else { return SyncError.offline }
    switch urlError.code {
    case .cancelled:
      return CancellationError()
    case .serverCertificateUntrusted, .serverCertificateHasBadDate,
      .serverCertificateHasUnknownRoot,
      .serverCertificateNotYetValid:
      return SyncError.pinningFailed
    default:
      return SyncError.offline
    }
  }
}

/// The in-flight task, for cancellation and for its identifier in the completion handler.
private final class TaskBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: URLSessionDataTask?
  var task: URLSessionDataTask? {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
  var identifier: Int { task?.taskIdentifier ?? -1 }
}

extension UUID {
  /// The contract's `Uuid`: lower-case.
  fileprivate var wire: String { uuidString.lowercased() }
}
