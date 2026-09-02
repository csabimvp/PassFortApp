import Foundation
import PassFortCrypto

// Uncomment the next line, run `swift build`, and it fails to compile.
// That failure IS the §4 layering guarantee -- PassFortVault cannot see PFCrypto.
// import PFCrypto

/// End-to-end vault entry points: they wire `VaultDatabase` + `VaultSession` +
/// `VaultRepository` together so callers (the CLI, the app) don't re-implement the
/// header-in-`vault_meta` dance.
public enum Vault {

  /// True if `databasePath` already holds an initialised vault (a §5.3 header).
  /// Cheap and side-effect-free — a read-only open and one query, no crypto, no
  /// migration. Lets the M3 GUI pick the Unlock vs. Create screen without a full
  /// `unlock` attempt.
  public static func exists(databasePath: String) -> Bool {
    VaultDatabase.vaultExists(atPath: databasePath)
  }

  /// Create a new vault at `databasePath`: seal a §5.3 header under `password`,
  /// initialise storage, verify. The database file must not already hold a vault.
  public static func create(
    databasePath: String, password: Data, params: KdfParameters, deviceID: UUID
  ) async throws -> VaultRepository {
    let database = try VaultDatabase(path: databasePath)
    let alreadyThere = try await database.dbQueue.read { db in
      try VaultMeta.read(db, .header) != nil
    }
    guard !alreadyThere else { throw VaultError.alreadyInitialized }

    let header = try VaultSession.create(password: password, params: params)
    let session = try VaultSession.open(header: header, password: password)
    return try await VaultRepository.bootstrap(
      database: database, session: session, header: header, deviceID: deviceID,
      highWater: HighWaterMark(sidecarFor: databasePath))
  }

  /// Like `create`, but also generates a recovery key and writes a two-slot header
  /// (§5.6, ADR-0007). The `RecoveryKey` is returned once and never stored -- the
  /// caller must show it to the user and discard it.
  public static func createWithRecovery(
    databasePath: String, password: Data, params: KdfParameters, deviceID: UUID
  ) async throws -> (repository: VaultRepository, recovery: RecoveryKey) {
    let database = try VaultDatabase(path: databasePath)
    let alreadyThere = try await database.dbQueue.read { db in
      try VaultMeta.read(db, .header) != nil
    }
    guard !alreadyThere else { throw VaultError.alreadyInitialized }

    let recovery = RecoveryKey.generate()
    let oneSlotHeader = try VaultSession.create(password: password, params: params)
    let session = try VaultSession.open(header: oneSlotHeader, password: password)
    let twoSlotHeader = try await session.addRecoverySlot(recoveryKey: recovery.raw)
    let repository = try await VaultRepository.bootstrap(
      database: database, session: session, header: twoSlotHeader, deviceID: deviceID,
      highWater: HighWaterMark(sidecarFor: databasePath))
    return (repository, recovery)
  }

  /// Recover a vault whose master password is lost: open via the recovery slot and
  /// immediately re-wrap to `newPassword`. **The recovery slot is consumed** -- the
  /// resulting header is password-only, so the caller should rotate in a fresh
  /// recovery key afterwards (`VaultRepository.rotateRecoveryKey`).
  public static func recover(
    databasePath: String, recoveryKey: RecoveryKey, newPassword: Data, deviceID: UUID
  ) async throws -> VaultRepository {
    let database = try VaultDatabase(path: databasePath)
    let oldHeader = try await database.dbQueue.read { db in
      guard let header = try VaultMeta.read(db, .header) else { throw VaultError.notFound }
      return header
    }
    let session = try VaultSession.openWithRecovery(
      header: oldHeader, recoveryKey: recoveryKey.raw)
    let newHeader = try await session.rewrap(newPassword: newPassword)
    try await database.dbQueue.write { db in try VaultMeta.write(db, .header, newHeader) }
    return try await VaultRepository.open(
      database: database, session: session, deviceID: deviceID,
      highWater: HighWaterMark(sidecarFor: databasePath))
  }

  /// Open an existing vault: migrate storage, read the stored header, unlock the
  /// crypto session, verify the manifest and the anti-rollback mark. Throws
  /// `.authFailed` for a wrong password or a corrupt header, `VaultManifest.Failure`
  /// for tamper or rollback.
  public static func unlock(
    databasePath: String, password: Data, deviceID: UUID, faultHook: FaultHook? = nil
  ) async throws -> VaultRepository {
    let database = try VaultDatabase(path: databasePath)
    let header = try await database.dbQueue.read { db in
      guard let header = try VaultMeta.read(db, .header) else { throw VaultError.notFound }
      return header
    }
    let session = try VaultSession.open(header: header, password: password)
    return try await VaultRepository.open(
      database: database, session: session, deviceID: deviceID,
      highWater: HighWaterMark(sidecarFor: databasePath), faultHook: faultHook)
  }

  /// Proves the allowed direction: PassFortVault -> PassFortCrypto (pure Swift API).
  public static func seamSelfTest(_ probe: Data) throws -> Data {
    try echo(probe)
  }
}
