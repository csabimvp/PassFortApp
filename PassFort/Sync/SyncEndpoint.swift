import Foundation

/// What a typed or pasted sync server address means: the API root, e.g.
/// `https://<site>.azurestaticapps.net/api/v1`. Whether it is acceptable -- https, or plain http to
/// loopback -- is `HTTPSyncAPI`'s decision, made before anything is sent.
nonisolated enum SyncEndpoint {
  /// The URL in `text`, trimmed, with no trailing slash; `nil` unless it is an absolute http(s)
  /// URL with a host.
  static func parse(_ text: String) -> URL? {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http", url.host() != nil
    else { return nil }
    return url
  }
}
