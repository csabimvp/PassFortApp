import Foundation

/// One HTTP exchange, as `HTTPSyncAPI` builds it.
struct SyncHTTPRequest: Sendable, Equatable {
  var method: String
  var url: URL
  var headers: [String: String]
  /// `nil` for no body at all.
  var body: Data?

  /// Header names are case-insensitive; look one up the way a server does.
  func header(_ name: String) -> String? { headers.value(forHeader: name) }
}

/// What came back: any status, the final response's headers, and the body.
struct SyncHTTPResponse: Sendable, Equatable {
  var status: Int
  var headers: [String: String]
  var body: Data

  func header(_ name: String) -> String? { headers.value(forHeader: name) }
}

/// Sends one request and returns whatever response the server gave, redirects included (never
/// followed). It throws only `SyncError.offline`, `.pinningFailed`, `.invalidResponse` (a response
/// the transport refuses, too large) or `CancellationError`. Status codes are `HTTPSyncAPI`'s to
/// map (ADR-0011, decision 4).
///
/// `URLSessionTransport` (with `PinnedTransport`) on Apple platforms; `CurlTransport` on Linux.
/// Both refuse redirects, use the same timeout, keep no cookies or cache, and pin every host but
/// loopback.
protocol SyncTransport: Sendable {
  func send(_ request: SyncHTTPRequest) async throws -> SyncHTTPResponse
}

extension Dictionary where Key == String, Value == String {
  fileprivate func value(forHeader name: String) -> String? {
    first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
  }
}
