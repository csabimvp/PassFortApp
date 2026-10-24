import Foundation

@testable import PassFortVault

/// The sync server in memory (`m5-sync.md` Phase 8): A.3's semantics as the real server
/// (`PassFortCloud`) implements them -- the all-or-nothing push against `baseVersion`, one gap-free
/// `seq` per record, the pull that records a device's `lastSeq`, the tombstone purge inside
/// `openSession`, and `410` once a cursor falls behind it. No HTTP, no crypto: it moves sealed blobs, as the real one does.
///
/// `onRequest` runs before every call and may throw (a dropped connection) or cancel the calling
/// task -- the call runs in the engine's task, so `withUnsafeCurrentTask { $0?.cancel() }` there
/// cancels the sync run at exactly that point.
actor FakeSyncServer: SyncAPI {
  enum Call: Sendable, Equatable {
    case createVault, openSession, header, putHeader, pull, push, devices, removeDevice,
      deleteVault
  }

  struct Device: Sendable {
    var name: String
    var platform: DevicePlatform
    var lastSeq: UInt64
    var lastSeenAt: Date
  }

  struct Vault: Sendable {
    var header: Data
    var headerVersion: UInt64 = 1
    var authKey: Data
    var seq: UInt64 = 0
    var purgedThroughSeq: UInt64 = 0
    var records: [UUID: RecordDTO] = [:]
    /// Every version ever pushed, for `replayOldVersion`.
    var history: [UUID: [RecordDTO]] = [:]
    var devices: [UUID: Device] = [:]
  }

  let enrollSecret: String
  private(set) var vaults: [UUID: Vault] = [:]
  private var tokens: [String: (vault: UUID, device: UUID)] = [:]
  private(set) var calls: [Call] = []
  private var onRequest: (@Sendable (Call) async throws -> Void)?

  init(enrollSecret: String = "enroll") {
    self.enrollSecret = enrollSecret
  }

  func setOnRequest(_ hook: (@Sendable (Call) async throws -> Void)?) {
    onRequest = hook
  }

  /// Every token stops working, as if they all expired: the next call is `401`.
  func expireTokens() {
    tokens = [:]
  }

  func vault(_ id: UUID) -> Vault? { vaults[id] }

  // MARK: - Faults: the hostile server (A.9, Phase 10)

  private var losePushResponse = false

  /// The next push is stored, but its response never arrives: the client sees `offline`.
  func loseNextPushResponse() {
    losePushResponse = true
  }

  /// Roll the vault's `seq` back, as a restored server would report it.
  func rewind(_ vaultID: UUID, seq: UInt64) {
    vaults[vaultID]?.seq = seq
  }

  /// Flip one bit of a stored record's `sealed`.
  func flipBit(_ vaultID: UUID, record: UUID) {
    guard var stored = vaults[vaultID]?.records[record], !stored.sealed.isEmpty else { return }
    stored.sealed[stored.sealed.startIndex] ^= 0x01
    vaults[vaultID]?.records[record] = stored
  }

  /// Lose a record outright, as if its entity were deleted from the table.
  func dropRecord(_ vaultID: UUID, record: UUID) {
    vaults[vaultID]?.records[record] = nil
  }

  /// Serve an older, genuine version of a record again, under a new `seq` -- a replay.
  func replayOldVersion(_ vaultID: UUID, record: UUID, version: UInt64) {
    guard var vault = vaults[vaultID],
      var old = vault.history[record]?.first(where: { $0.version == version })
    else { return }
    vault.seq += 1
    old.seq = vault.seq
    vault.records[record] = old
    vaults[vaultID] = vault
  }

  /// Corrupt the stored header (one bit of its wrapped DEK) -- what a forging server serves a
  /// joining device.
  func forgeHeader(_ vaultID: UUID) {
    guard var header = vaults[vaultID]?.header, header.count > 60 else { return }
    header[header.startIndex + 60] ^= 0x01
    vaults[vaultID]?.header = header
  }

  // MARK: - Operations a test drives directly

  /// Purge every tombstone up to `seq` and raise `purgedThroughSeq` -- as the opportunistic purge
  /// would once every device had pulled that far.
  func purge(_ vaultID: UUID, through seq: UInt64) {
    guard var vault = vaults[vaultID] else { return }
    for record in vault.records.values where record.isDeleted && record.seq <= seq {
      vault.records[record.id] = nil
    }
    vault.purgedThroughSeq = max(vault.purgedThroughSeq, seq)
    vaults[vaultID] = vault
  }

  /// Settings -> Devices -> Remove, without a token.
  func unregister(_ vaultID: UUID, device: UUID) {
    vaults[vaultID]?.devices[device] = nil
  }

  // MARK: - SyncAPI

  func createVault(_ request: CreateVaultRequest, enrollSecret: String) async throws
    -> CreateVaultResponse
  {
    try await begin(.createVault)
    guard enrollSecret == self.enrollSecret else { throw SyncError.forbidden }
    guard vaults[request.vaultId] == nil else { throw SyncError.vaultExists }
    var vault = Vault(header: request.header, authKey: request.authKey)
    vault.devices[request.device.id] = Device(
      name: request.device.name, platform: request.device.platform, lastSeq: 0, lastSeenAt: Date())
    vaults[request.vaultId] = vault
    return CreateVaultResponse(seq: 0, headerVersion: 1)
  }

  func openSession(vaultID: UUID, _ request: SessionRequest) async throws -> SessionResponse {
    try await begin(.openSession)
    guard var vault = vaults[vaultID], vault.authKey == request.authKey else {
      throw SyncError.unauthorized
    }
    let known = vault.devices[request.device.id]
    vault.devices[request.device.id] = Device(
      name: request.device.name, platform: request.device.platform,
      lastSeq: known?.lastSeq ?? 0, lastSeenAt: Date())
    Self.purge(&vault)
    vaults[vaultID] = vault

    let token = "token-\(UUID().uuidString.lowercased())"
    tokens[token] = (vaultID, request.device.id)
    return SessionResponse(
      token: token, expiresAt: Date().addingTimeInterval(900), seq: vault.seq,
      headerVersion: vault.headerVersion, purgedThroughSeq: vault.purgedThroughSeq)
  }

  func header(vaultID: UUID) async throws -> HeaderResponse {
    try await begin(.header)
    guard let vault = vaults[vaultID] else { throw SyncError.notFound }
    return HeaderResponse(header: vault.header, headerVersion: vault.headerVersion)
  }

  func putHeader(vaultID: UUID, header: Data, base: UInt64, token: String) async throws -> UInt64 {
    try await begin(.putHeader)
    _ = try authorize(token, vaultID)
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
    let device = try authorize(token, vaultID)
    guard var vault = vaults[vaultID] else { throw SyncError.unauthorized }
    if since > 0 && since < vault.purgedThroughSeq { throw SyncError.resyncRequired }
    vault.devices[device]?.lastSeq = since
    vault.devices[device]?.lastSeenAt = Date()
    vaults[vaultID] = vault

    let after = vault.records.values.filter { $0.seq > since }.sorted { $0.seq < $1.seq }
    let page = min(max(limit, 1), SyncEngine.pageLimit)
    return ChangesResponse(
      records: Array(after.prefix(page)), seq: vault.seq, hasMore: after.count > page,
      headerVersion: vault.headerVersion, purgedThroughSeq: vault.purgedThroughSeq)
  }

  func push(vaultID: UUID, _ records: [PushDTO], token: String) async throws -> PushResponse {
    try await begin(.push)
    let writer = try authorize(token, vaultID)
    guard var vault = vaults[vaultID] else { throw SyncError.unauthorized }
    guard (1...99).contains(records.count),
      Set(records.map(\.id)).count == records.count,
      records.allSatisfy({ $0.version > $0.baseVersion })
    else { throw SyncError.badRequest }

    let conflicts = records.compactMap { record -> ConflictDTO? in
      let serverVersion = vault.records[record.id]?.version ?? 0
      return serverVersion == record.baseVersion
        ? nil : ConflictDTO(id: record.id, serverVersion: serverVersion)
    }
    guard conflicts.isEmpty else { throw SyncError.conflicts(conflicts) }

    var applied: [AppliedDTO] = []
    for record in records {
      vault.seq += 1
      let stored = RecordDTO(
        id: record.id, version: record.version, hlc: record.hlc, sealed: record.sealed,
        isDeleted: record.isDeleted, seq: vault.seq, writer: writer)
      vault.records[record.id] = stored
      vault.history[record.id, default: []].append(stored)
      applied.append(AppliedDTO(id: record.id, version: record.version, seq: vault.seq))
    }
    vaults[vaultID] = vault
    if losePushResponse {
      losePushResponse = false
      throw SyncError.offline
    }
    return PushResponse(applied: applied, seq: vault.seq)
  }

  func devices(vaultID: UUID, token: String) async throws -> [DeviceInfoDTO] {
    try await begin(.devices)
    _ = try authorize(token, vaultID)
    guard let vault = vaults[vaultID] else { throw SyncError.unauthorized }
    return vault.devices.map { id, device in
      DeviceInfoDTO(
        id: id, name: device.name, platform: device.platform, lastSeq: device.lastSeq,
        lastSeenAt: device.lastSeenAt)
    }
  }

  func removeDevice(vaultID: UUID, deviceID: UUID, token: String) async throws {
    try await begin(.removeDevice)
    _ = try authorize(token, vaultID)
    guard vaults[vaultID]?.devices.removeValue(forKey: deviceID) != nil else {
      throw SyncError.notFound
    }
  }

  func deleteVault(vaultID: UUID, token: String) async throws {
    try await begin(.deleteVault)
    _ = try authorize(token, vaultID)
    vaults[vaultID] = nil
  }

  // MARK: - Internals

  private func begin(_ call: Call) async throws {
    calls.append(call)
    try await onRequest?(call)
    try Task.checkCancellation()  // as a cancelled URLSession task fails
  }

  /// The token's device; `401` for an unknown token or another vault's.
  private func authorize(_ token: String, _ vaultID: UUID) throws -> UUID {
    guard let claims = tokens[token], claims.vault == vaultID else { throw SyncError.unauthorized }
    return claims.device
  }

  /// A.10: every tombstone each registered device has pulled past goes, and
  /// `purgedThroughSeq` rises to the highest one purged.
  private static func purge(_ vault: inout Vault) {
    guard let minSeq = vault.devices.values.map(\.lastSeq).min(), minSeq > 0 else { return }
    let purged = vault.records.values.filter { $0.isDeleted && $0.seq <= minSeq }
    guard let highest = purged.map(\.seq).max() else { return }
    for record in purged { vault.records[record.id] = nil }
    vault.purgedThroughSeq = max(vault.purgedThroughSeq, highest)
  }
}
