import Foundation

/// A stable per-install device id for the sync clock (HLC) and, in M5, server registration.
///
/// Created once and kept in the Keychain, so it survives relaunches and an app-container reset. It
/// does not survive losing the Keychain, which is acceptable: M5 registers the id server-side on
/// first sync anyway.
nonisolated enum DeviceIdentity {
  static let service = "app.passfort.device-id"

  /// The id for `account`, minted on first use. If the Keychain is unavailable the id is fresh and
  /// not persisted: a record written under it is still correct, just attributed to a one-off device.
  static func current(service: String = service, account: String = "default") -> UUID {
    if let stored = try? Keychain.get(service: service, account: account),
      let text = String(data: stored, encoding: .utf8), let id = UUID(uuidString: text)
    {
      return id
    }
    let id = UUID()
    try? Keychain.set(Data(id.uuidString.utf8), service: service, account: account)
    return id
  }
}
