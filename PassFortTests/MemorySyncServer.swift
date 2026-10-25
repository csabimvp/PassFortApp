import Foundation
import PassFortVault

/// A sync server in memory for the app's tests: the A.3 semantics the engine relies on -- the
/// all-or-nothing push against `baseVersion`, one gap-free `seq` per record, sessions keyed by
/// `k_auth` -- and nothing else (no purge, no hostile modes; `PassFortVaultTests` has those).
/// Moves sealed blobs and never decrypts, as the real one does.
///
/// `onRequest` runs before every call and may throw (a failure) or suspend (a slow network).
actor MemorySyncServer: SyncAPI {
  enum Call: Sendable, Equatable {
    case createVault, openSession, header, putHeader, pull, push, devices, removeDevice,
      deleteVault
  }

  private struct Vault {
    var header: Data
    var headerVersion: UInt64 = 1
    var authKey: Data
    var seq: UInt64 = 0
    var records: [UUID: RecordDTO] = [:]
    var devices: [UUID: DeviceInfoDTO] = [:]
  }

  static let enrollSecret = "enroll"

  private var vaults: [UUID: Vault] = [:]
  private var tokens: [String: (vault: UUID, device: UUID)] = [:]
  private var onRequest: (@Sendable (Call) async throws -> Void)?

  func setOnRequest(_ hook: (@Sendable (Call) async throws -> Void)?) {
    onRequest = hook
  }

  func recordCount(_ vaultID: UUID) -> Int { vaults[vaultID]?.records.count ?? 0 }
  var vaultIDs: [UUID] { Array(vaults.keys) }

  // MARK: - SyncAPI

  func createVault(_ request: CreateVaultRequest, enrollSecret: String) async throws
    -> CreateVaultResponse
  {
    try await begin(.createVault)
    guard enrollSecret == Self.enrollSecret else { throw SyncError.forbidden }
    guard vaults[request.vaultId] == nil else { throw SyncError.vaultExists }
    vaults[request.vaultId] = Vault(header: request.header, authKey: request.authKey)
    register(request.device, in: request.vaultId)
    return CreateVaultResponse(seq: 0, headerVersion: 1)
  }

  func openSession(vaultID: UUID, _ request: SessionRequest) async throws -> SessionResponse {
    try await begin(.openSession)
    guard let vault = vaults[vaultID], vault.authKey == request.authKey else {
      throw SyncError.unauthorized
    }
    register(request.device, in: vaultID)
    let token = UUID().uuidString
    tokens[token] = (vaultID, request.device.id)
    return SessionResponse(
      token: token, expiresAt: Date().addingTimeInterval(900), seq: vault.seq,
      headerVersion: vault.headerVersion, purgedThroughSeq: 0)
  }

  func header(vaultID: UUID) async throws -> HeaderResponse {
    try await begin(.header)
    guard let vault = vaults[vaultID] else { throw SyncError.notFound }
    return HeaderResponse(header: vault.header, headerVersion: vault.headerVersion)
  }

  func putHeader(vaultID: UUID, header: Data, base: UInt64, token: String) async throws -> UInt64 {
    try await begin(.putHeader)
    try authorize(token, vaultID)
    guard var vault = vaults[vaultID] else { throw SyncError.unauthorized }
    guard base == vault.headerVersion else {
      throw SyncError.headerConflict(headerVersion: vault.headerVersion)
    }
    vault.header = header
    vault.headerVersion += 1
    vaults[vaultID] = vault
    return vault.headerVersion
  }

  func changes(vaultID: UUID, since: UInt64, limit: Int, token: String) async throws
    -> ChangesResponse
  {
    try await begin(.pull)
    try authorize(token, vaultID)
    guard let vault = vaults[vaultID] else { throw SyncError.unauthorized }
    let after = vault.records.values.filter { $0.seq > since }.sorted { $0.seq < $1.seq }
    return ChangesResponse(
      records: Array(after.prefix(limit)), seq: vault.seq, hasMore: after.count > limit,
      headerVersion: vault.headerVersion, purgedThroughSeq: 0)
  }

  func push(vaultID: UUID, _ records: [PushDTO], token: String) async throws -> PushResponse {
    try await begin(.push)
    let writer = try authorize(token, vaultID)
    guard var vault = vaults[vaultID] else { throw SyncError.unauthorized }
    let conflicts = records.compactMap { record -> ConflictDTO? in
      let serverVersion = vault.records[record.id]?.version ?? 0
      return serverVersion == record.baseVersion
        ? nil : ConflictDTO(id: record.id, serverVersion: serverVersion)
    }
    guard conflicts.isEmpty else { throw SyncError.conflicts(conflicts) }

    var applied: [AppliedDTO] = []
    for record in records {
      vault.seq += 1
      vault.records[record.id] = RecordDTO(
        id: record.id, version: record.version, hlc: record.hlc, sealed: record.sealed,
        isDeleted: record.isDeleted, seq: vault.seq, writer: writer)
      applied.append(AppliedDTO(id: record.id, version: record.version, seq: vault.seq))
    }
    vaults[vaultID] = vault
    return PushResponse(applied: applied, seq: vault.seq)
  }

  func devices(vaultID: UUID, token: String) async throws -> [DeviceInfoDTO] {
    try await begin(.devices)
    try authorize(token, vaultID)
    return vaults[vaultID].map { Array($0.devices.values) } ?? []
  }

  func removeDevice(vaultID: UUID, deviceID: UUID, token: String) async throws {
    try await begin(.removeDevice)
    try authorize(token, vaultID)
    guard vaults[vaultID]?.devices.removeValue(forKey: deviceID) != nil else {
      throw SyncError.notFound
    }
  }

  func deleteVault(vaultID: UUID, token: String) async throws {
    try await begin(.deleteVault)
    try authorize(token, vaultID)
    vaults[vaultID] = nil
  }

  // MARK: - Internals

  private func begin(_ call: Call) async throws {
    try await onRequest?(call)
    try Task.checkCancellation()
  }

  @discardableResult
  private func authorize(_ token: String, _ vaultID: UUID) throws -> UUID {
    guard let claims = tokens[token], claims.vault == vaultID else { throw SyncError.unauthorized }
    return claims.device
  }

  private func register(_ device: DeviceDTO, in vaultID: UUID) {
    vaults[vaultID]?.devices[device.id] = DeviceInfoDTO(
      id: device.id, name: device.name, platform: device.platform, lastSeq: 0, lastSeenAt: Date())
  }
}
