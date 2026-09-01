import Foundation

internal import PFCrypto

/// The Sendable Swift view of the vault header's `kdf_*` fields (architecture §7.4).
///
/// This is the one model type that crosses the seam: `pf_kdf_calibrate` produces
/// it, `VaultSession.create` consumes it, and `PassFortVault` persists it in the
/// header blob. It carries no C++ type, so `PassFortVault` can use it without the
/// interop flag.
public struct KdfParameters: Sendable, Equatable, Codable {
  /// KDF identifier. `1` = Argon2id (the only value in M1).
  public var kdfID: UInt8
  /// Memory cost, in KiB.
  public var memoryKiB: UInt32
  /// Time cost (number of passes).
  public var iterations: UInt32
  /// Parallelism (lanes).
  public var parallelism: UInt32
  /// 16 bytes, drawn from the OS CSPRNG at vault-creation time.
  public var salt: Data

  public init(
    kdfID: UInt8, memoryKiB: UInt32, iterations: UInt32, parallelism: UInt32, salt: Data
  ) {
    self.kdfID = kdfID
    self.memoryKiB = memoryKiB
    self.iterations = iterations
    self.parallelism = parallelism
    self.salt = salt
  }
}

// MARK: - Bridging to the POD `pf.KdfParams`

extension KdfParameters {
  /// Build from the value `pf_kdf_calibrate` returned.
  init(_ c: pf.KdfParams) {
    self.kdfID = UInt8(truncatingIfNeeded: c.kdf_id)
    self.memoryKiB = c.m_kib
    self.iterations = c.t
    self.parallelism = c.p

    var bytes = Data(count: 16)
    withUnsafeBytes(of: c.salt) { src in
      bytes.withUnsafeMutableBytes { dst in
        guard let s = src.baseAddress, let d = dst.baseAddress else { return }
        d.copyMemory(from: s, byteCount: min(src.count, dst.count))
      }
    }
    self.salt = bytes
  }

  /// The POD form the seam expects. A `salt` that is not exactly 16 bytes is
  /// zero-padded / truncated into the fixed C array.
  var cParams: pf.KdfParams {
    var c = pf.KdfParams()
    c.kdf_id = Int32(kdfID)
    c.m_kib = memoryKiB
    c.t = iterations
    c.p = parallelism
    salt.withUnsafeBytes { src in
      withUnsafeMutableBytes(of: &c.salt) { dst in
        guard let s = src.baseAddress, let d = dst.baseAddress else { return }
        d.copyMemory(from: s, byteCount: min(src.count, dst.count))
      }
    }
    return c
  }
}
