import Foundation

/// The monotonic `vault_version` high-water mark, kept *outside* the vault file
/// (§5.5) so a whole-file rollback is detectable even though the rolled-back file
/// is internally consistent. M2 CLI: a `0600` sidecar next to the database. M4
/// moves this into the Keychain -- same contract, different backing store.
///
/// A missing file reads as 0: a vault that has never been written. The unlock path
/// tolerates the file being *ahead* of the mark (a crash between the commit and the
/// bump) and repairs it forward; it rejects the file being *behind* (a rollback).
public struct HighWaterMark: Sendable {
  private let url: URL

  /// The sidecar for a vault at `databasePath` -- `<databasePath>.hw`, alongside
  /// SQLite's own `-wal` / `-shm`.
  public init(sidecarFor databasePath: String) {
    self.url = URL(fileURLWithPath: databasePath + ".hw")
  }

  /// An explicit location -- used by tests and by M4's Keychain shim.
  public init(url: URL) {
    self.url = url
  }

  public func read() throws -> UInt64 {
    guard let data = try? Data(contentsOf: url), data.count == 8 else { return 0 }
    return data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
  }

  public func write(_ version: UInt64) throws {
    var bigEndian = version.bigEndian
    let data = withUnsafeBytes(of: &bigEndian) { Data($0) }
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
  }

  /// Clear the mark -- a deliberate, explicit act (`passfort-cli verify
  /// --accept-restore`, Phase 10), the only sanctioned way to accept a restored
  /// backup.
  public func reset() throws {
    try? FileManager.default.removeItem(at: url)
  }
}
