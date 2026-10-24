import Foundation
import PassFortCrypto

extension Vault {
  /// Join a vault another device put on the sync server (A.11 `join`): fetch its header, unlock it
  /// with `password`, and build an empty local vault on it with sync configured. The first
  /// `SyncEngine.run` then pulls every record. `databasePath` must not already hold a vault.
  ///
  /// The header comes over an unauthenticated endpoint, so this is where a forged one is caught:
  /// it fails to unwrap here, before `k_auth` exists -- nothing is sent to the server and nothing
  /// is written (A.9).
  ///
  /// - Throws: `PassFortError.authFailed` for a wrong password or a forged header,
  ///   `VaultError.alreadyInitialized`, or the `SyncError` of the header fetch.
  public static func join(
    databasePath: String, password: Data, api: any SyncAPI, endpoint: URL, vaultID: UUID,
    deviceID: UUID, highWater: HighWaterMark? = nil, wallClock: WallClock = .system
  ) async throws -> VaultRepository {
    guard !exists(databasePath: databasePath) else { throw VaultError.alreadyInitialized }
    let fetched = try await api.header(vaultID: vaultID)
    let session = try VaultSession.open(header: fetched.header, password: password)

    let repository = try await VaultRepository.bootstrap(
      database: try VaultDatabase(path: databasePath), session: session, header: fetched.header,
      deviceID: deviceID, highWater: highWater ?? HighWaterMark(sidecarFor: databasePath),
      wallClock: wallClock)
    try await repository.enableSync(
      SyncConfig(endpoint: endpoint, vaultID: vaultID, enabledAt: Date()),
      headerVersion: fetched.headerVersion)
    return repository
  }

  /// Accept a vault file restored from a backup: clear the anti-rollback mark, so the next unlock
  /// accepts the older `vault_version` and repairs the mark forward (§5.5), and -- with sync on --
  /// reset `sync_cursor`, so the next run is a full resync that brings the file up to the server
  /// and re-uploads what only the backup has (A.10). Needs no password: neither is covered by the
  /// manifest. The cursor goes first, so a failure leaves the mark in place and the step can be
  /// repeated.
  public static func acceptRestoredBackup(
    databasePath: String, highWater: HighWaterMark? = nil
  ) async throws {
    let database = try VaultDatabase(path: databasePath)
    try await database.dbQueue.write { db in
      if try VaultMeta.readSyncConfig(db) != nil { try VaultMeta.writeSyncCursor(db, 0) }
    }
    try (highWater ?? HighWaterMark(sidecarFor: databasePath)).reset()
  }
}
