#if os(Linux)
  import CLinuxTLS
  import Foundation

  /// `SyncTransport` over libcurl with OpenSSL (ADR-0011): `URLSession` on Linux can't pin and
  /// can't require TLS 1.3. `pf_tls_send` verifies the chain the normal way, then requires a pinned
  /// SPKI hash anywhere in it, root included, with TLS 1.3 as the floor, no redirects and the same
  /// timeout. A libcurl that can't run that check refuses to send (`.pinningFailed`). Loopback
  /// hosts skip pinning, as on the Mac.
  final class CurlTransport: SyncTransport {
    private let pins: PinSet

    init(pins: PinSet) {
      self.pins = pins
    }

    func send(_ request: SyncHTTPRequest) async throws -> SyncHTTPResponse {
      let cancel = CancelFlag()
      let pins = pins
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          // curl_easy_perform blocks, so it gets a thread of its own, off the cooperative pool.
          Thread.detachNewThread {
            continuation.resume(
              with: Result { try Self.perform(request, pins: pins, cancel: cancel) })
          }
        }
      } onCancel: {
        cancel.set()
      }
    }

    static func perform(_ request: SyncHTTPRequest, pins: PinSet, cancel: CancelFlag) throws
      -> SyncHTTPResponse
    {
      let lines = request.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
      // A NUL would cut the line short in C; CR and LF would start a header of their own.
      // Bytes, not Characters: "\r\n" is a single Character, so a lone CR would slip past one.
      guard !lines.contains(where: { $0.utf8.contains { [0x0D, 0x0A, 0x00].contains($0) } }) else {
        throw SyncError.badRequest
      }
      let pinBytes = pins.hashes.sorted { $0.lexicographicallyPrecedes($1) }.flatMap { $0 }
      let skipPinning = PinSet.isLoopback(host: request.url.host())

      var response = pf_tls_response()
      defer { pf_tls_response_free(&response) }
      let status = withCStrings(lines) { headerLines in
        request.method.withCString { method in
          request.url.absoluteString.withCString { url in
            pinBytes.withUnsafeBufferPointer { pinBuffer in
              (request.body ?? Data()).withUnsafeBytes { body in
                var c = pf_tls_request(
                  method: method, url: url, headers: headerLines.baseAddress,
                  header_count: headerLines.count, has_body: request.body == nil ? 0 : 1,
                  body: body.bindMemory(to: UInt8.self).baseAddress, body_len: body.count,
                  pins: pinBuffer.baseAddress, pin_count: pins.hashes.count,
                  skip_pinning: skipPinning ? 1 : 0,
                  timeout_seconds: Int(HTTPSyncAPI.requestTimeout), cancel: cancel.pointer)
                return pf_tls_send(&c, &response)
              }
            }
          }
        }
      }

      switch status {
      case PF_TLS_OK:
        return SyncHTTPResponse(
          status: Int(response.status),
          headers: parseHeaders(bytes(response.headers, response.headers_len)),
          body: bytes(response.body, response.body_len))
      case PF_TLS_UNTRUSTED, PF_TLS_UNSUPPORTED: throw SyncError.pinningFailed
      case PF_TLS_CANCELLED: throw CancellationError()
      case PF_TLS_TOO_LARGE: throw SyncError.invalidResponse
      case PF_TLS_BAD_INPUT: throw SyncError.badRequest
      default: throw SyncError.offline
      }
    }

    /// The final response's header lines (`Name: value`, CRLF-separated, after the status line).
    /// A repeated header's values are joined with `, `, as HTTP allows.
    static func parseHeaders(_ raw: Data) -> [String: String] {
      var headers: [String: String] = [:]
      for line in String(decoding: raw, as: UTF8.self).split(whereSeparator: \.isNewline) {
        guard let colon = line.firstIndex(of: ":"), !line.hasPrefix("HTTP/") else { continue }
        let name = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { continue }
        headers[name] = headers[name].map { "\($0), \(value)" } ?? value
      }
      return headers
    }

    private static func bytes(_ pointer: UnsafeRawPointer?, _ count: Int) -> Data {
      guard let pointer, count > 0 else { return Data() }
      return Data(bytes: pointer, count: count)
    }

    /// Calls `body` with the strings as C strings, valid only inside it.
    private static func withCStrings<Result>(
      _ strings: [String], _ body: (UnsafeBufferPointer<UnsafePointer<CChar>?>) -> Result
    ) -> Result {
      let copies = strings.map { strdup($0) }
      defer { for copy in copies { free(copy) } }
      return copies.map { $0.map(UnsafePointer.init) }.withUnsafeBufferPointer(body)
    }
  }

  /// `pf_tls_cancel`, owned: set from the task's cancellation handler, read by libcurl's progress
  /// callback on the request's thread.
  final class CancelFlag: @unchecked Sendable {
    let pointer: OpaquePointer?

    init() {
      pointer = pf_tls_cancel_new()
    }

    func set() { pf_tls_cancel_set(pointer) }

    deinit { pf_tls_cancel_free(pointer) }
  }
#endif
