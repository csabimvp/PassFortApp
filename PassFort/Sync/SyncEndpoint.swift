import Foundation

/// What a typed or pasted sync server address means: the API root, e.g.
/// `https://<site>.azurestaticapps.net/api/v1`. Whether it is acceptable -- https, or plain http to
/// loopback -- is `HTTPSyncAPI`'s decision, made before anything is sent.
nonisolated enum SyncEndpoint {
  /// The URL in `text`, trimmed, with no trailing slash; `nil` unless it is an absolute http(s)
  /// URL with a host. A bare host gains `apiRoot`: the site's own root serves the static page,
  /// which answers every API request with a 405.
  static func parse(_ text: String) -> URL? {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http", url.host() != nil
    else { return nil }
    return url.path().isEmpty ? url.appending(path: apiRoot) : url
  }

  /// Where the API lives on a PassFort server (`SyncAPI/openapi.yaml`).
  static let apiRoot = "api/v1"

  /// The server this Mac last turned sync on with or joined through, to fill in next time -- an
  /// address, not a secret.
  static var lastUsed: URL? {
    get { UserDefaults.standard.url(forKey: lastUsedKey) }
    set { UserDefaults.standard.set(newValue, forKey: lastUsedKey) }
  }

  private static let lastUsedKey = "lastSyncEndpoint"
}

/// What another device needs to join a synced vault -- the server and the vault id, and nothing
/// secret: the master password is still needed to open what the server holds. Shared as text or
/// a QR code (`AddDeviceSheet`) in the form `passfort://join?endpoint=<url>&vault=<uuid>`, which
/// the iPhone client (M7) reads too.
nonisolated struct SyncInvite: Equatable, Identifiable {
  var endpoint: URL
  var vaultID: UUID

  var id: UUID { vaultID }

  static let scheme = "passfort"

  var url: URL {
    var components = URLComponents()
    components.scheme = Self.scheme
    components.host = "join"
    components.queryItems = [
      URLQueryItem(name: "endpoint", value: endpoint.absoluteString),
      URLQueryItem(name: "vault", value: vaultID.uuidString.lowercased()),
    ]
    return components.url ?? endpoint
  }

  /// The invite in `text`, or `nil` if it isn't one.
  static func parse(_ text: String) -> SyncInvite? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let components = URLComponents(string: trimmed),
      components.scheme?.lowercased() == scheme, components.host == "join"
    else { return nil }
    let items = components.queryItems ?? []
    guard let endpointText = items.first(where: { $0.name == "endpoint" })?.value,
      let endpoint = SyncEndpoint.parse(endpointText),
      let vaultText = items.first(where: { $0.name == "vault" })?.value,
      let vaultID = UUID(uuidString: vaultText)
    else { return nil }
    return SyncInvite(endpoint: endpoint, vaultID: vaultID)
  }
}
