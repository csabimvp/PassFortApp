import Foundation

internal import PFCrypto

/// Wraps one `pf_mac_init` / `update` / `finish` / `free` cycle — the streaming
/// anti-rollback MAC (§5.5).
///
/// The caller decides the iteration order (records sorted by UUID); C++ holds
/// `k_manifest` and does the hashing. `finish()` consumes it; after that every
/// call throws.
///
/// `@unchecked Sendable` so a `VaultSession` can hand one back: the underlying
/// `pf::Mac` is a standalone HMAC object, independent of the session's memory.
/// It is **not** safe for concurrent use — one builder, one task, top to bottom.
public final class ManifestBuilder: @unchecked Sendable {
  private var handle: OpaquePointer?  // pf::Mac*

  init(handle: OpaquePointer) {
    self.handle = handle
  }

  deinit {
    if let handle {
      pf.pf_mac_free(handle)
    }
  }

  /// Fold one record into the MAC: `SHA-256(sealed)` is computed inside C++, then
  /// `recordID ‖ version ‖ that hash` goes into the running HMAC. Call once per
  /// record, in ascending `recordID` order.
  public func update(recordID: UUID, version: UInt64, sealed: Data) throws {
    guard let handle else { throw PassFortError.badInput }
    let status = withUnsafeBytes(of: recordID.uuid) { id in
      sealed.withUnsafeBytes { s in
        pf.pf_mac_update(
          handle, id.bindMemory(to: UInt8.self).baseAddress, version,
          s.bindMemory(to: UInt8.self).baseAddress, s.count)
      }
    }
    guard status == pf.Status.Ok else { throw PassFortError(status) }
  }

  /// Finalize and return the 32-byte MAC. Single-shot: frees the handle, and any
  /// further call throws.
  public func finish() throws -> Data {
    guard let handle else { throw PassFortError.badInput }
    self.handle = nil
    defer { pf.pf_mac_free(handle) }
    return try consume(pf.pf_mac_finish(handle))
  }
}
