import Foundation
import PassFortCrypto

/// What one `run` did -- for `passfort-cli sync now` and the status line.
public struct SyncReport: Sendable, Equatable {
  /// Records received from the server (echoes of this device's own pushes included).
  public var pulled = 0
  /// Records the server accepted from this device.
  public var pushed = 0
  /// Conflict copies made (A.7).
  public var conflictCopies = 0
  /// The run was a full resync (A.10) ...
  public var fullResync = false
  /// ... and found this many rows the server lacked, uploaded again.
  public var reuploaded = 0

  public init() {}

  mutating func add(_ other: SyncReport) {
    pulled += other.pulled
    pushed += other.pushed
    conflictCopies += other.conflictCopies
    fullResync = fullResync || other.fullResync
    reuploaded += other.reuploaded
  }
}

/// Where a sync run is, for the status line (A.11).
public enum SyncPhase: Sendable, Equatable {
  case connecting
  case pulling
  case pushing
  case compacting
}

/// What `SyncEngine` publishes. Phase 13's `SyncController` turns `problem` into the A.11 sheet
/// or footer.
public enum SyncStatus: Sendable, Equatable {
  /// No `sync_config`.
  case off
  /// Between runs; `nil` until the first run on this unlock finishes.
  case idle(lastSyncedAt: Date?)
  case syncing(SyncPhase)
  /// The last run couldn't reach the server. Normal, and retried on the next trigger.
  case offline
  /// The last run stopped on something the next trigger may not fix by itself.
  case problem(SyncError)
}

/// One vault's sync client: runs `m5-sync.md` A.6 against a `SyncAPI` -- session, pull and
/// reconcile page by page, push, compact. It adds no crypto of its own (§9.1): it asks the
/// repository for `k_auth` and to open, seal and commit.
///
/// Every ingest is one repository commit, so a run cancelled or killed at any point leaves the
/// vault verifying; the next run picks up from the last committed cursor. The session token
/// lives here, in memory only, for one run.
///
/// A pull from cursor 0 is a full resync (A.10): after joining, after accepting a restored
/// backup, and after a `410`. Rows the server didn't return are uploaded again -- never deleted.
public actor SyncEngine {
  /// `GET /changes` page size -- the contract's ceiling.
  static let pageLimit = 500
  /// A push batch: the contract's record limit, and a body budget under its 3 MiB with room for
  /// the JSON around the records.
  static let batchRecords = 99
  static let batchBytes = 3 * 1024 * 1024 - 64 * 1024
  /// Push-conflict rounds before a run gives up and leaves the rest to the next one (A.6 step 4).
  static let conflictRounds = 3
  /// Re-plans of one page when a local write lands while it is being planned.
  static let staleRetries = 3

  private let api: any SyncAPI
  private let repository: VaultRepository
  private let device: DeviceDTO

  private var token: String?
  /// The server's `headerVersion` as of the latest session or page this run.
  private var serverHeaderVersion: UInt64 = 0
  private var running = false
  private var runAgain = false
  private var lastSyncedAt: Date?
  /// The run in progress so far.
  private var report = SyncReport()

  /// Status changes, newest kept if nobody is reading. One consumer (the app's `SyncController`).
  public nonisolated let statusUpdates: AsyncStream<SyncStatus>
  private let statusContinuation: AsyncStream<SyncStatus>.Continuation

  /// - Parameter device: this device as the server sees it; its `id` must be the repository's
  ///   device id, which stamps every local write.
  public init(api: any SyncAPI, repository: VaultRepository, device: DeviceDTO) {
    self.api = api
    self.repository = repository
    self.device = device
    (statusUpdates, statusContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(1))
  }

  deinit {
    statusContinuation.finish()
  }

  // MARK: - Enabling

  /// Put this vault on the server for the first time (`POST /vaults`) under a fresh random
  /// vaultId -- a 122-bit capability, not the header's vault UUID -- and record it in
  /// `sync_config`. Nothing is pushed yet: the next `run` uploads every row.
  ///
  /// - Returns: the vaultId other devices join with.
  @discardableResult
  public func enable(endpoint: URL, enrollSecret: String) async throws -> UUID {
    let vaultID = UUID()
    let created = try await api.createVault(
      CreateVaultRequest(
        vaultId: vaultID, header: try await repository.header(),
        authKey: try await repository.authKey(), device: device),
      enrollSecret: enrollSecret)
    try await repository.enableSync(
      SyncConfig(endpoint: endpoint, vaultID: vaultID, enabledAt: Date()),
      headerVersion: created.headerVersion)
    return vaultID
  }

  // MARK: - Running

  /// Sync now. Single-flight: called while a run is in progress, it asks that run to go round
  /// once more when it finishes and returns at once, with an empty report.
  ///
  /// - Returns: what the run did, every round of it.
  /// - Throws: the `SyncError` (or storage error) that stopped the run, after publishing it;
  ///   `CancellationError` if the calling task was cancelled -- the vault is consistent either
  ///   way.
  @discardableResult
  public func run() async throws -> SyncReport {
    guard !running else {
      runAgain = true
      return SyncReport()
    }
    running = true
    defer { running = false }
    var total = SyncReport()
    repeat {
      runAgain = false
      report = SyncReport()
      try await runOnce()
      total.add(report)
    } while runAgain
    return total
  }

  private func runOnce() async throws {
    do {
      guard let config = try await repository.syncConfig() else { throw SyncError.notEnabled }
      publish(.syncing(.connecting))
      token = nil
      _ = try await currentToken(config)

      publish(.syncing(.pulling))
      try await pull(config)
      let headerLost = try await syncHeader(config)

      var round = 0
      while true {
        publish(.syncing(.pushing))
        do {
          try await push(config)
          break
        } catch SyncError.conflicts(let conflicts) {
          // Someone pushed between our pull and our push: pull again, which reconciles them.
          round += 1
          if round >= Self.conflictRounds { throw SyncError.conflicts(conflicts) }
          publish(.syncing(.pulling))
          try await pull(config)
        }
      }

      publish(.syncing(.compacting))
      try await repository.compactSynced()
      token = nil
      lastSyncedAt = Date()
      try await repository.recordSyncFinished(at: lastSyncedAt ?? Date())
      // Reported once the records are in: they synced; only this device's header change didn't.
      if headerLost { throw SyncError.headerChangedElsewhere }
      publish(.idle(lastSyncedAt: lastSyncedAt))
    } catch {
      token = nil
      switch error {
      case is CancellationError: publish(.idle(lastSyncedAt: lastSyncedAt))
      case SyncError.notEnabled: publish(.off)
      case SyncError.offline: publish(.offline)
      case let error as SyncError: publish(.problem(error))
      default: publish(.idle(lastSyncedAt: lastSyncedAt))
      }
      throw error
    }
  }

  // MARK: - Session (A.6 step 1)

  /// The run's token, opening a session for it if there is none. The server's `seq` must not be
  /// behind what this vault already ingested (A.9).
  private func currentToken(_ config: SyncConfig) async throws -> String {
    if let token { return token }
    try Task.checkCancellation()
    let opened = try await api.openSession(
      vaultID: config.vaultID,
      SessionRequest(authKey: try await repository.authKey(), device: device))
    guard opened.seq >= (try await repository.syncCursor()) else { throw SyncError.serverRollback }
    serverHeaderVersion = opened.headerVersion
    token = opened.token
    return opened.token
  }

  /// Make an authenticated call; on `401` (the token expired mid-run) open a new session and try
  /// once more.
  private func authorized<T: Sendable>(
    _ config: SyncConfig, _ call: (String) async throws -> T
  ) async throws -> T {
    try Task.checkCancellation()
    do {
      return try await call(try await currentToken(config))
    } catch SyncError.unauthorized {
      token = nil
      return try await call(try await currentToken(config))
    }
  }

  // MARK: - Pull (A.6 step 2)

  /// Pull every page after the cursor and ingest it. From cursor 0 this is a full resync (A.10):
  /// the stored cursor stays at 0 until the last page has landed, then every synced row the
  /// server didn't return is marked never-synced, so the push uploads it again. A resync cut
  /// short is simply redone. A `410` (tombstones after the cursor were purged) resets the cursor
  /// to 0 and starts one.
  private func pull(_ config: SyncConfig) async throws {
    let floor = try await repository.syncCursor()
    let full = floor == 0
    var since = floor
    var purgedThrough: UInt64 = 0
    var returned = Set<UUID>()
    while true {
      let from = since
      let page: ChangesResponse
      do {
        page = try await authorized(config) { token in
          try await self.api.changes(
            vaultID: config.vaultID, since: from, limit: Self.pageLimit, token: token)
        }
      } catch SyncError.resyncRequired where !full {
        try await repository.resetSyncCursor()
        return try await pull(config)
      }
      guard page.seq >= floor else { throw SyncError.serverRollback }
      serverHeaderVersion = page.headerVersion
      purgedThrough = page.purgedThroughSeq
      // Ascending, after `since`, within the server's own high-water mark, one entry per id --
      // and a page that says there is more has something in it.
      guard page.records.allSatisfy({ $0.seq > from && $0.seq <= page.seq }),
        zip(page.records, page.records.dropFirst()).allSatisfy({ $0.seq < $1.seq }),
        Set(page.records.map(\.id)).count == page.records.count,
        !(page.hasMore && page.records.isEmpty)
      else { throw SyncError.invalidResponse }

      if let last = page.records.last {
        try await ingest(page.records, cursor: full ? 0 : last.seq)
        report.pulled += page.records.count
        since = last.seq
        if full { returned.formUnion(page.records.map(\.id)) }
      }
      if !page.hasMore { break }
    }
    // Finishing at the purge mark too: otherwise a vault whose newest entries were purged
    // tombstones would stay below it and resync on every run. Nothing is skipped by it --
    // nothing can be purged while this device's pull from 0 holds the server's minimum
    // `lastSeq` at 0, so every live record at or under the mark was in the scan.
    if full {
      report.fullResync = true
      report.reuploaded += try await repository.finishResync(
        serverHas: returned, cursor: max(since, purgedThrough))
    }
  }

  /// Reconcile one page and commit it with its cursor. Planning reads the local rows first and
  /// seals outside the transaction; a local write in between makes the commit stale, and the
  /// page is planned again.
  private func ingest(_ records: [RecordDTO], cursor: UInt64) async throws {
    var attempt = 1
    while true {
      try Task.checkCancellation()
      let plan = try await plan(records)
      do {
        try await repository.applyRemote(plan, cursor: cursor)
        report.conflictCopies += plan.conflictCopies.count
        return
      } catch VaultError.staleWrite where attempt < Self.staleRetries {
        attempt += 1
      }
    }
  }

  /// A.7 over a page, in `seq` order. Every record must open before anything is planned: one
  /// that doesn't is a forgery, and the whole page is refused (A.9).
  private func plan(_ records: [RecordDTO]) async throws -> ReconcilePlan {
    var remotePayloads: [AccountPayload] = []
    remotePayloads.reserveCapacity(records.count)
    for record in records {
      do {
        remotePayloads.append(try await repository.payload(of: record))
      } catch {
        throw SyncError.tamperedRecord(record.id)
      }
    }

    let snapshot = try await repository.rowsForIngest(records.map(\.id))
    var plan = ReconcilePlan(vaultVersion: snapshot.vaultVersion)

    for (remote, remotePayload) in zip(records, remotePayloads) {
      await repository.clock.receive(remote.hlc.hlc)
      let local = snapshot.rows[remote.id]
      var payloads: Reconciler.ConflictPayloads?
      if let local, Reconciler.isConflict(local: local, remote: remote) {
        payloads = .init(local: try await repository.payload(of: local), remote: remotePayload)
      }

      switch Reconciler.decide(local: local, remote: remote, payloads: payloads) {
      case .ignore:
        break
      case .confirm:
        plan.confirmations.append(
          PushedRecord(id: remote.id, version: remote.version, seq: remote.seq))
      case .insert, .fastForward:
        plan.rows.append(SealedRecord(remote))
      case .takeRemote(let copyLocal):
        if copyLocal, let payloads {
          plan.conflictCopies.append(
            try await repository.conflictCopy(of: remote.id, payload: payloads.local))
        }
        plan.rows.append(SealedRecord(remote))
      case .keepLocal(let copyRemote):
        guard let local, let payloads else { break }  // unreachable: a conflict has both
        var row = try await repository.resealed(
          local, payload: payloads.local, at: remote.version + 1)
        row.syncedVersion = remote.version
        row.syncedSeq = remote.seq
        plan.rows.append(row)
        if copyRemote {
          plan.conflictCopies.append(
            try await repository.conflictCopy(of: remote.id, payload: remotePayload))
        }
      }
    }
    return plan
  }

  // MARK: - Devices and the server copy (A.11)

  /// Every device registered for this vault (`GET /devices`).
  public func devices() async throws -> [DeviceInfoDTO] {
    let config = try await enabledConfig()
    defer { token = nil }
    return try await authorized(config) { token in
      try await self.api.devices(vaultID: config.vaultID, token: token)
    }
  }

  /// Remove a device, so it stops holding back the server's tombstone purge. If it syncs again it
  /// gets `410` and resyncs (A.10).
  public func removeDevice(_ deviceID: UUID) async throws {
    let config = try await enabledConfig()
    defer { token = nil }
    try await authorized(config) { token in
      try await self.api.removeDevice(vaultID: config.vaultID, deviceID: deviceID, token: token)
    }
  }

  /// Delete the whole server copy (`DELETE /vaults/{id}`). This vault keeps every record; turning
  /// sync off locally is `VaultRepository.disableSync`.
  public func deleteServerCopy() async throws {
    let config = try await enabledConfig()
    defer { token = nil }
    try await authorized(config) { token in
      try await self.api.deleteVault(vaultID: config.vaultID, token: token)
    }
  }

  private func enabledConfig() async throws -> SyncConfig {
    guard let config = try await repository.syncConfig() else { throw SyncError.notEnabled }
    return config
  }

  // MARK: - Header (A.6 step 3, A.8)

  /// Push this device's header change, or fetch another device's to adopt at the next unlock.
  /// Nothing is adopted while unlocked: the session keeps working on the same DEK either way.
  ///
  /// - Returns: true if this device's change lost to another device's (`409`) -- the server's
  ///   header is then pending and the local change discarded.
  private func syncHeader(_ config: SyncConfig) async throws -> Bool {
    let state = try await repository.headerSyncState()
    if state.dirty {
      do {
        let version = try await authorized(config) { token in
          try await self.api.putHeader(
            vaultID: config.vaultID, header: state.header, base: state.headerVersion ?? 0,
            token: token)
        }
        try await repository.headerPushed(state.header, headerVersion: version)
        return false
      } catch SyncError.headerConflict {
        try await fetchPendingHeader(
          config, newerThan: state.headerVersion ?? 0, discardingLocalChange: true)
        return true
      }
    }

    let known = max(state.headerVersion ?? 0, state.pending?.headerVersion ?? 0)
    if serverHeaderVersion > known {
      try await fetchPendingHeader(config, newerThan: known, discardingLocalChange: false)
    }
    return false
  }

  /// `GET /header` into `pending_header`, if it is newer than `newerThan`. Unauthenticated, like
  /// the endpoint: whatever the server returns is only adopted if this vault's password opens it
  /// and the manifest verifies under it.
  private func fetchPendingHeader(
    _ config: SyncConfig, newerThan known: UInt64, discardingLocalChange: Bool
  ) async throws {
    try Task.checkCancellation()
    let fetched = try await api.header(vaultID: config.vaultID)
    guard fetched.headerVersion > known else { return }
    try await repository.storePendingHeader(
      PendingHeader(headerVersion: fetched.headerVersion, header: fetched.header),
      discardingLocalChange: discardingLocalChange)
  }

  // MARK: - Push (A.6 step 4)

  /// Push every dirty row in batches. A `409` means another device got in first; it is thrown
  /// for `runOnce` to pull and try again. Batches before it stay pushed.
  private func push(_ config: SyncConfig) async throws {
    let dirty = try await repository.dirtyRecords()
    for batch in Self.batches(dirty.map(PushDTO.init)) {
      let response = try await authorized(config) { token in
        try await self.api.push(vaultID: config.vaultID, batch, token: token)
      }
      try await repository.markPushed(response.applied.map(\.pushed))
      report.pushed += response.applied.count
    }
  }

  /// Split a push into batches of at most `batchRecords` records and about `batchBytes` of body.
  /// A single record over the byte budget still goes alone; the server answers `413` for it.
  static func batches(_ records: [PushDTO]) -> [[PushDTO]] {
    var batches: [[PushDTO]] = []
    var current: [PushDTO] = []
    var bytes = 0
    for record in records {
      let size = (record.sealed.count + 2) / 3 * 4 + 400  // base64 + the JSON around it
      if !current.isEmpty && (current.count == batchRecords || bytes + size > batchBytes) {
        batches.append(current)
        current = []
        bytes = 0
      }
      current.append(record)
      bytes += size
    }
    if !current.isEmpty { batches.append(current) }
    return batches
  }

  private func publish(_ status: SyncStatus) {
    statusContinuation.yield(status)
  }
}
