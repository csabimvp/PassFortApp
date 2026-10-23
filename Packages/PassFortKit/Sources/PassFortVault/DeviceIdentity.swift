import Foundation

/// Who this install is, to the HLC (the stamp's device) and to the sync server (its device row):
/// a random id and a human name, created on first use (`m5-sync.md` A.5).
///
/// Stored **outside** the vault file, on purpose: a vault copied, restored or moved onto another
/// machine must not bring its device with it, or two installs would stamp and sync as one. The
/// app keeps it at `defaultURL`, inside its sandbox container; the CLI keeps its own.
public struct DeviceIdentity: Codable, Sendable, Equatable {
  public var id: UUID
  public var name: String

  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }

  /// `Application Support/PassFort/device.json` -- beside the default vault, inside the sandbox
  /// container for the app.
  public static var defaultURL: URL {
    URL.applicationSupportDirectory.appending(path: "PassFort/device.json")
  }

  /// This Mac's name as the user set it ("Alice's MacBook Air"), for a new identity.
  public static var hostName: String {
    Host.current().localizedName ?? ProcessInfo.processInfo.hostName
  }

  /// The identity stored at `url`, or -- when there is no file -- a new one with a random id and
  /// `name`, written there (`0600`, directory `0700`) before it is returned.
  ///
  /// - Throws: if the file exists but can't be read or decoded. It is never replaced silently: a
  ///   new id would make this install a stranger to its own sync server.
  public static func loadOrCreate(at url: URL, name: @autoclosure () -> String) throws
    -> DeviceIdentity
  {
    let path = url.path(percentEncoded: false)
    if FileManager.default.fileExists(atPath: path) {
      return try JSONDecoder().decode(DeviceIdentity.self, from: Data(contentsOf: url))
    }

    let identity = DeviceIdentity(id: UUID(), name: name())
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(identity).write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    return identity
  }
}
