import Foundation

/// The sync API, one method per endpoint (`m5-sync.md` A.3, 7.2). `HTTPSyncAPI` is the real one;
/// Phase 8's `FakeSyncServer` implements the same semantics in memory so the engine can be tested
/// headless. Every method throws `SyncError`.
///
/// Stateless: the caller (the engine) holds the session token, in memory only.
public protocol SyncAPI: Sendable {
  /// `POST /vaults` -- behind the enrollment secret.
  func createVault(_ request: CreateVaultRequest, enrollSecret: String) async throws
    -> CreateVaultResponse
  /// `POST /vaults/{id}/session` -- trade `k_auth` for a 15-minute token.
  func openSession(vaultID: UUID, _ request: SessionRequest) async throws -> SessionResponse
  /// `GET /vaults/{id}/header` -- unauthenticated: a joining device needs it before it has a key.
  func header(vaultID: UUID) async throws -> HeaderResponse
  /// `PUT /vaults/{id}/header` -- returns the new `headerVersion`.
  func putHeader(vaultID: UUID, header: Data, base: UInt64, token: String) async throws -> UInt64
  /// `GET /vaults/{id}/changes?since=&limit=` -- one page, ascending by `seq`.
  func changes(vaultID: UUID, since: UInt64, limit: Int, token: String) async throws
    -> ChangesResponse
  /// `POST /vaults/{id}/changes` -- one atomic batch of 1...99 records.
  func push(vaultID: UUID, _ records: [PushDTO], token: String) async throws -> PushResponse
  /// `GET /vaults/{id}/devices`.
  func devices(vaultID: UUID, token: String) async throws -> [DeviceInfoDTO]
  /// `DELETE /vaults/{id}/devices/{deviceId}`.
  func removeDevice(vaultID: UUID, deviceID: UUID, token: String) async throws
  /// `DELETE /vaults/{id}` -- the whole server copy.
  func deleteVault(vaultID: UUID, token: String) async throws
}
