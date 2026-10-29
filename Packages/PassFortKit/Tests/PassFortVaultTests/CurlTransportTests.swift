#if os(Linux)
  import CLinuxTLS
  import Foundation
  import Glibc
  import Testing

  @testable import PassFortVault

  /// `CurlTransport` and `pf_tls_send` (ADR-0011) against a one-shot HTTP server on 127.0.0.1:
  /// what goes out, what comes back, and the refusals. Loopback skips pinning, as on the Mac, so
  /// the pinned path is `LinuxPinningTests` (offline) and the Phase 6 drill (against Azure).
  @Suite struct CurlTransportTests {

    private let pins = PinSet(hashes: [Data(count: 32)])

    private func get(_ url: URL) -> SyncHTTPRequest {
      SyncHTTPRequest(method: "GET", url: url, headers: [:], body: nil)
    }

    // MARK: - Requests and responses

    @Test func sendsMethodHeadersAndBodyAndReadsTheResponse() async throws {
      let server = try LoopbackServer(
        response:
          "HTTP/1.1 503 Service Unavailable\r\nRetry-After: 7\r\nContent-Length: 4\r\n\r\nbusy")
      let request = SyncHTTPRequest(
        method: "PUT", url: try server.url("/api/v1/x"),
        headers: ["X-PassFort-Token": "tok", "Content-Type": "application/json"],
        body: Data(#"{"a":1}"#.utf8))

      let response = try await CurlTransport(pins: pins).send(request)
      #expect(response.status == 503)
      #expect(response.header("retry-after") == "7")
      #expect(response.body == Data("busy".utf8))

      let sent = server.request()
      #expect(sent.hasPrefix("PUT /api/v1/x HTTP/1.1\r\n"), "\(sent)")
      #expect(sent.contains("\r\nX-PassFort-Token: tok\r\n"))
      #expect(sent.hasSuffix("\r\n\r\n{\"a\":1}"))
      #expect(!sent.lowercased().contains("\r\nexpect:"), "no 100-continue round trip")
    }

    @Test func aGetSendsNoBody() async throws {
      let server = try LoopbackServer(response: "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}")
      let response = try await CurlTransport(pins: pins).send(get(try server.url("/h")))
      #expect(response.status == 200 && response.body == Data("{}".utf8))
      let sent = server.request().lowercased()
      #expect(sent.hasPrefix("get /h http/1.1\r\n"))
      #expect(!sent.contains("content-length") && sent.hasSuffix("\r\n\r\n"))
    }

    @Test func aRedirectComesBackUnfollowed() async throws {
      let server = try LoopbackServer(
        response:
          "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/x\r\nContent-Length: 0\r\n\r\n")
      let response = try await CurlTransport(pins: pins).send(get(try server.url("/")))
      #expect(response.status == 302)
      #expect(response.header("Location") == "http://127.0.0.1:1/x")
    }

    @Test func headersParseAsTheFinalResponseHasThem() {
      let raw = Data(
        "HTTP/1.1 200 OK\r\nVary: a\r\nVary: b\r\nRetry-After:  3 \r\nno colon here\r\n\r\n".utf8)
      #expect(CurlTransport.parseHeaders(raw) == ["Vary": "a, b", "Retry-After": "3"])
    }

    // MARK: - Failures and refusals

    @Test func aClosedPortIsOffline() async throws {
      let request = get(try #require(URL(string: "http://127.0.0.1:1/")))
      await #expect(throws: SyncError.offline) {
        _ = try await CurlTransport(pins: pins).send(request)
      }
    }

    @Test(arguments: ["a\r\nX-Evil: 1", "a\nX-Evil: 1", "a\rb", "a\0b"])
    func aHeaderThatCouldSplitIsRefusedBeforeSending(_ value: String) async throws {
      var request = get(try #require(URL(string: "http://127.0.0.1:1/")))
      request.headers["X-PassFort-Enroll"] = value
      await #expect(throws: SyncError.badRequest) {
        _ = try await CurlTransport(pins: pins).send(request)
      }
    }

    @Test func cancellingStopsARequestInFlight() async throws {
      let server = try LoopbackServer(
        response: "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n", delay: 30)
      let request = get(try server.url("/slow"))
      let started = Date()
      let task = Task { [pins] in try await CurlTransport(pins: pins).send(request) }
      try await Task.sleep(for: .milliseconds(300))
      task.cancel()
      await #expect(throws: CancellationError.self) { _ = try await task.value }
      #expect(Date().timeIntervalSince(started) < 10, "stopped by the cancel, not the timeout")
    }

    /// The C layer's own guard: `CurlTransport` never asks for this (loopback skips pins, and
    /// `HTTPSyncAPI` refuses plain http anywhere else), but a pinned request over http must stop
    /// before a byte -- and the token in it -- goes out.
    @Test func pinningOverPlainHTTPIsRefusedBeforeSending() throws {
      let server = try LoopbackServer(response: "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
      let pin = [UInt8](repeating: 0, count: 32)
      var response = pf_tls_response()
      let status = "GET".withCString { method in
        "http://127.0.0.1:\(server.port)/".withCString { url in
          pin.withUnsafeBufferPointer { pins in
            var request = pf_tls_request(
              method: method, url: url, headers: nil, header_count: 0, has_body: 0, body: nil,
              body_len: 0, pins: pins.baseAddress, pin_count: 1, skip_pinning: 0,
              timeout_seconds: 5, cancel: nil)
            return pf_tls_send(&request, &response)
          }
        }
      }
      #expect(status == PF_TLS_BAD_INPUT)
      #expect(server.request(timeout: 0.5).isEmpty, "nothing reached the server")
    }
  }

  /// A one-shot HTTP/1.1 server on 127.0.0.1: accepts one connection, reads one request (headers,
  /// then `Content-Length` bytes), answers with `response` after `delay`, and closes. Releasing the
  /// server cuts a delay short, so no thread outlives its test (LeakSanitizer would count it).
  final class LoopbackServer: @unchecked Sendable {
    struct Failure: Error {}

    let port: UInt16
    private let listener: Int32
    private let received = Locked(initialState: Data())
    private let answered = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    init(response: String, delay: TimeInterval = 0) throws {
      let listener = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
      guard listener >= 0 else { throw Failure() }
      var address = sockaddr_in()
      address.sin_family = sa_family_t(AF_INET)
      address.sin_addr.s_addr = inet_addr("127.0.0.1")
      address.sin_port = 0
      var length = socklen_t(MemoryLayout<sockaddr_in>.size)
      let ready = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(listener, $0, length) == 0 && listen(listener, 1) == 0
            && getsockname(listener, $0, &length) == 0
        }
      }
      guard ready else {
        close(listener)
        throw Failure()
      }
      self.listener = listener
      port = UInt16(bigEndian: address.sin_port)

      let received = received
      let answered = answered
      let released = released
      Thread.detachNewThread {
        defer { answered.signal() }
        let connection = accept(listener, nil, nil)
        guard connection >= 0 else { return }
        defer { close(connection) }
        let request = Self.readRequest(connection)
        received.withLock { $0 = request }
        if delay > 0 { _ = released.wait(timeout: .now() + delay) }
        let bytes = Array(response.utf8)
        _ = bytes.withUnsafeBytes {
          send(connection, $0.baseAddress, $0.count, Int32(MSG_NOSIGNAL))
        }
      }
    }

    deinit {
      released.signal()  // ends a delay still running
      shutdown(listener, Int32(SHUT_RDWR))  // wakes an accept() still waiting
      close(listener)
    }

    func url(_ path: String) throws -> URL {
      try #require(URL(string: "http://127.0.0.1:\(port)\(path)"))
    }

    /// The raw request, once the server has answered (or after `timeout`, whatever arrived).
    func request(timeout: TimeInterval = 10) -> String {
      _ = answered.wait(timeout: .now() + timeout)
      return String(decoding: received.withLock { $0 }, as: UTF8.self)
    }

    private static func readRequest(_ connection: Int32) -> Data {
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while true {
        if let end = data.range(of: Data("\r\n\r\n".utf8)) {
          let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).lowercased()
          let length =
            head.split(separator: "\r\n").lazy
            .compactMap { line -> Int? in
              guard line.hasPrefix("content-length:") else { return nil }
              return Int(
                line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
            }
            .first ?? 0
          if data.count - end.upperBound >= length { return data }
        }
        let count = recv(connection, &buffer, buffer.count, 0)
        guard count > 0 else { return data }
        data.append(buffer, count: count)
      }
    }
  }
#endif
