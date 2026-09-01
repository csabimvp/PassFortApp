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

  // MARK: - Records

  /// Seal `plaintext` for the record identified by `recordID` / `version` /
  /// `schema` — those three plus the vault UUID are bound as the AEAD AAD (§5.4).
  /// Returns `nonce ‖ ciphertext ‖ tag`.
  public func seal(recordID: UUID, version: UInt64, schema: UInt16, plaintext: Data) throws -> Data
  {
    try withUnsafeBytes(of: recordID.uuid) { id in
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
    try withUnsafeBytes(of: recordID.uuid) { id in
      try sealed.withUnsafeBytes { s in
        try consume(
          pf.pf_open(
            handle, id.bindMemory(to: UInt8.self).baseAddress, version, schema,
            s.bindMemory(to: UInt8.self).baseAddress, s.count))
      }
    }
  }

  // MARK: - Manifest

  /// Start a streaming anti-rollback MAC over the vault at `vaultVersion` (§5.5).
  /// The caller (`PassFortVault`, inside a write transaction) then folds its own
  /// rows in UUID order via `ManifestBuilder.update`.
  public func makeManifestBuilder(vaultVersion: UInt64) throws -> ManifestBuilder {
    ManifestBuilder(handle: try consume(pf.pf_mac_init(handle, vaultVersion)))
  }
}
