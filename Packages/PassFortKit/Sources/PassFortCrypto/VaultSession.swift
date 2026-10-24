import Foundation
internal import PFCrypto

/// Owns the opaque C++ session handle for one unlocked vault.
///
/// An `actor` because the C++ session is single-owner and deliberately not
/// thread-safe (architecture §6.4), and because Argon2id blocks for the better
/// part of a second — running that off any UI thread comes for free here.
///
/// `import PFCrypto` appears in this module and nowhere else. Every `pf.Status`
/// is translated to a `PassFortError`; a wrong password and a tampered header
/// both surface as `.authFailed`, so this API is not a decryption oracle either
/// (architecture §13.1).
public actor VaultSession {
  // Set once in `init`, never mutated; the C++ session is single-owner. The
  // `unsafe` opt-out lets `deinit` (nonisolated) close it. `OpaquePointer` is
  // not `Sendable` in this toolchain, hence the annotation rather than a plain
  // `let`.
  nonisolated(unsafe) private let handle: OpaquePointer  // pf::Session*

  private init(handle: OpaquePointer) {
    self.handle = handle
  }

  deinit {
    // Scrubs RootKeys / DEK / DekSubkeys, then frees. `deinit` timing is not
    // guaranteed immediate; an explicit auto-lock lands in M3 (§12).
    pf.pf_session_close(handle)
  }

  // MARK: - Lifecycle

  /// Measure Argon2id on this machine and return parameters that take ~`targetMs`.
  /// Blocks while it runs a few trial hashes.
  public static func calibrate(targetMs: UInt32) throws -> KdfParameters {
    KdfParameters(try consume(pf.pf_kdf_calibrate(targetMs)))
  }

  /// Create a vault: a random DEK and vault UUID, wrapped under `password` with
  /// `params`. Returns the §5.3 header blob to persist. Blocks on Argon2id.
  public static func create(password: Data, params: KdfParameters) throws -> Data {
    let c = params.cParams
    return try password.withUnsafeBytes { pw in
      try consume(
        pf.pf_vault_create(pw.bindMemory(to: UInt8.self).baseAddress, pw.count, c))
    }
  }

  /// Open a session from a stored header + password. Blocks on Argon2id.
  /// Throws `.authFailed` for a wrong password *or* a corrupt header.
  public static func open(header: Data, password: Data) throws -> VaultSession {
    let handle = try header.withUnsafeBytes { h in
      try password.withUnsafeBytes { pw in
        try consume(
          pf.pf_session_open(
            h.bindMemory(to: UInt8.self).baseAddress, h.count,
            pw.bindMemory(to: UInt8.self).baseAddress, pw.count))
      }
    }
    return VaultSession(handle: handle)
  }

  /// Re-wrap the same DEK under a new password (same KDF cost, fresh salt).
  /// Returns the new header blob; this session switches to the new keys.
  public func rewrap(newPassword: Data) throws -> Data {
    try newPassword.withUnsafeBytes { pw in
      try consume(
        pf.pf_session_rewrap(handle, pw.bindMemory(to: UInt8.self).baseAddress, pw.count))
    }
  }

  // MARK: - Recovery key (§5.6, ADR-0007)

  /// Add a recovery slot: returns a new two-slot header wrapping this session's
  /// DEK under both the password KEK and `recoveryKey` (must be exactly 32 bytes,
  /// from the system CSPRNG). Requires a password-opened session; a
  /// recovery-opened one throws `.badInput` (rewrap to a password first).
  public func addRecoverySlot(recoveryKey: Data) throws -> Data {
    guard recoveryKey.count == 32 else { throw PassFortError.badInput }
    return try recoveryKey.withUnsafeBytes { rk in
      try consume(pf.pf_recovery_wrap(handle, rk.bindMemory(to: UInt8.self).baseAddress))
    }
  }

  /// Open a session from a stored header via the recovery slot. Throws
  /// `.notFound` if the vault has no recovery slot, `.authFailed` for a wrong
  /// key. The session carries no password keys, so the caller must `rewrap` to a
  /// new password before it can `addRecoverySlot`. It can sync as-is: `authKey()`
  /// hangs off the DEK (ADR-0009).
  public static func openWithRecovery(header: Data, recoveryKey: Data) throws -> VaultSession {
    guard recoveryKey.count == 32 else { throw PassFortError.badInput }
    let handle = try header.withUnsafeBytes { h in
      try recoveryKey.withUnsafeBytes { rk in
        try consume(
          pf.pf_recovery_open(
            h.bindMemory(to: UInt8.self).baseAddress, h.count,
            rk.bindMemory(to: UInt8.self).baseAddress))
      }
    }
    return VaultSession(handle: handle)
  }

  /// The vault UUID (a plaintext §5.3 field, not a secret) -- identifies the
  /// vault for sync and plaintext export.
  public func vaultUUID() throws -> UUID {
    var bytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    let status = withUnsafeMutableBytes(of: &bytes) { buffer in
      pf.pf_session_vault_uuid(handle, buffer.bindMemory(to: UInt8.self).baseAddress)
    }
    guard status == pf.Status.Ok else { throw PassFortError(status) }
    return UUID(uuid: bytes)
  }

  /// The vault UUID written in `header`, read without opening it -- no password, no
  /// Argon2. **Unauthenticated**: use it only to compare identities, as adopting a
  /// header another device pushed does (`m5-sync.md` A.8). Throws `.badInput` for a
  /// short or foreign buffer, `.unsupported` for an unknown format.
  public static func vaultUUID(ofHeader header: Data) throws -> UUID {
    var bytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    let status = header.withUnsafeBytes { h in
      withUnsafeMutableBytes(of: &bytes) { out in
        pf.pf_header_vault_uuid(
          h.bindMemory(to: UInt8.self).baseAddress, h.count,
          out.bindMemory(to: UInt8.self).baseAddress)
      }
    }
    guard status == pf.Status.Ok else { throw PassFortError(status) }
    return UUID(uuid: bytes)
  }

  /// The sync credential `k_auth` (ADR-0009): 32 bytes the sync server
  /// authenticates this vault with, storing only their SHA-256. Derived from the
  /// DEK, so it is the same on every device and survives `rewrap` and recovery.
  /// The one key-derived value that leaves the C++ core -- send it to the sync
  /// server over TLS and nowhere else; never log or persist it.
  public func authKey() throws -> Data {
    var key = Data(count: 32)
    let status = key.withUnsafeMutableBytes { buffer in
      pf.pf_session_auth_key(handle, buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
    }
    guard status == pf.Status.Ok else { throw PassFortError(status) }
    return key
  }

  // MARK: - Records

  /// Seal `plaintext` for the record identified by `recordID` / `version` /
  /// `schema` — those three plus the vault UUID are bound as the AEAD AAD (§5.4).
  /// Returns `nonce ‖ ciphertext ‖ tag`.
  public func seal(recordID: UUID, version: UInt64, schema: UInt16, plaintext: Data) throws -> Data
  {
    defer { sealCount &+= 1 }
    return try withUnsafeBytes(of: recordID.uuid) { id in
      try plaintext.withUnsafeBytes { pt in
        try consume(
          pf.pf_seal(
            handle, id.bindMemory(to: UInt8.self).baseAddress, version, schema,
            pt.bindMemory(to: UInt8.self).baseAddress, pt.count))
      }
    }
  }

  /// Open a sealed blob. The identity fields must match what it was sealed with,
  /// or this throws `.authFailed` (the §5.4 binding). Returns the plaintext.
  public func open(recordID: UUID, version: UInt64, schema: UInt16, sealed: Data) throws -> Data {
    defer { openCount &+= 1 }
    return try withUnsafeBytes(of: recordID.uuid) { id in
      try sealed.withUnsafeBytes { s in
        try consume(
          pf.pf_open(
            handle, id.bindMemory(to: UInt8.self).baseAddress, version, schema,
            s.bindMemory(to: UInt8.self).baseAddress, s.count))
      }
    }
  }

  // MARK: - Stats

  /// Crypto operation counts, for a UI "under the hood" panel — not a security
  /// property, so counted on every call including a failed `open` (a wrong
  /// version/schema binding, say): the AEAD primitive still ran.
  public struct CryptoStats: Sendable, Equatable {
    public let sealCount: UInt64
    public let openCount: UInt64
  }

  private var sealCount: UInt64 = 0
  private var openCount: UInt64 = 0

  public func cryptoStats() -> CryptoStats {
    CryptoStats(sealCount: sealCount, openCount: openCount)
  }

  // MARK: - Manifest

  /// Start a streaming anti-rollback MAC over the vault at `vaultVersion` (§5.5).
  /// The caller (`PassFortVault`, inside a write transaction) then folds its own
  /// rows in UUID order via `ManifestBuilder.update`.
  public func makeManifestBuilder(vaultVersion: UInt64) throws -> ManifestBuilder {
    ManifestBuilder(handle: try consume(pf.pf_mac_init(handle, vaultVersion)))
  }
}
