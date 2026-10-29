#if canImport(Security)
  import Foundation
  import Testing

  @testable import PassFortVault

  /// `URLSessionTransport` against a `URLProtocol` stub: what goes out, what comes back, how
  /// `URLError`s map, and that `PinnedTransport` refuses redirects. Pinning itself is
  /// `PinningTests`.
  @Suite struct URLSessionTransportTests {

    // MARK: - Stub

    /// One canned reply, or a transport error.
    struct Reply: Sendable {
      var status = 200
      var headers: [String: String] = [:]
      var body = Data()
      var error: URLError?
    }

    /// Routes by the first path segment, a per-test id, so suites running in parallel never see
    /// each other's requests.
    final class Stub: URLProtocol, @unchecked Sendable {
      private static let routes = Locked(
        initialState: [String: (reply: Reply, captured: [SyncHTTPRequest])]())

      static func register(_ id: String, _ reply: Reply) {
        routes.withLock { $0[id] = (reply, []) }
      }

      static func captured(_ id: String) -> [SyncHTTPRequest] {
        routes.withLock { $0[id]?.captured ?? [] }
      }

      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

      override func startLoading() {
        guard let url = request.url else { return }
        let id = url.pathComponents.dropFirst().first ?? ""
        let capture = SyncHTTPRequest(
          method: request.httpMethod ?? "", url: url,
          headers: request.allHTTPHeaderFields ?? [:],
          body: request.httpBodyStream.map(Self.read) ?? request.httpBody)
        guard
          let reply = Self.routes.withLock({ routes -> Reply? in
            routes[id]?.captured.append(capture)
            return routes[id]?.reply
          })
        else { return client?.urlProtocol(self, didFailWithError: URLError(.badURL)) ?? () }

        if let error = reply.error {
          return client?.urlProtocol(self, didFailWithError: error) ?? ()
        }
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

    /// A transport whose requests land in the stub under a fresh id, and that id's URL.
    private func stubbed(_ reply: Reply) throws -> (URLSessionTransport, URL, String) {
      let id = UUID().uuidString
      Stub.register(id, reply)
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [Stub.self]
      let url = try #require(URL(string: "https://sync.test/\(id)/api/v1/vaults"))
      return (URLSessionTransport(pins: .none, configuration: configuration), url, id)
    }

    // MARK: - Requests and responses

    @Test func sendsTheRequestAndReturnsTheResponse() async throws {
      let (transport, url, id) = try stubbed(
        Reply(status: 503, headers: ["Retry-After": "7"], body: Data("busy".utf8)))
      let request = SyncHTTPRequest(
        method: "PUT", url: url, headers: ["X-PassFort-Token": "tok"], body: Data("{}".utf8))

      let response = try await transport.send(request)
      #expect(response.status == 503)
      #expect(response.header("retry-after") == "7")
      #expect(response.body == Data("busy".utf8))

      let sent = try #require(Stub.captured(id).first)
      #expect(sent.method == "PUT")
      #expect(sent.header("X-PassFort-Token") == "tok")
      #expect(sent.body == Data("{}".utf8))
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
      let (transport, url, _) = try stubbed(Reply(error: URLError(code)))
      let request = SyncHTTPRequest(method: "GET", url: url, headers: [:], body: nil)
      await #expect(throws: expected) { _ = try await transport.send(request) }
    }

    @Test func theDelegateRefusesEveryRedirect() async {
      let delegate = PinnedTransport(pins: .none)
      let session = URLSession(configuration: .ephemeral)
      let task = session.dataTask(with: URL(string: "https://sync.test/a")!)
      let redirect = HTTPURLResponse(
        url: URL(string: "https://sync.test/a")!, statusCode: 302, httpVersion: nil,
        headerFields: ["Location": "http://evil.test/a"])!
      let followed = await withCheckedContinuation { continuation in
        delegate.urlSession(
          session, task: task, willPerformHTTPRedirection: redirect,
          newRequest: URLRequest(url: URL(string: "http://evil.test/a")!)
        ) { continuation.resume(returning: $0) }
      }
      #expect(followed == nil)
      session.invalidateAndCancel()
    }
  }
#endif
