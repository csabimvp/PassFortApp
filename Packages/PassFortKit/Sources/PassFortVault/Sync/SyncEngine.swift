import Foundation
import PassFortCrypto

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
/// session for `k_auth` and the repository to open, seal and commit.
///
/// Every ingest is one repository commit, so a run cancelled or killed at any point leaves the
/// vault verifying; the next run picks up from the last committed cursor. The session token
/// lives here, in memory only, for one run.
///
/// Header sync (step 3, Phase 9) and full resync on `410` (A.10, Phase 10) are not wired yet: a
/// `410` ends the run with `SyncError.resyncRequired`.
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
  private let session: VaultSession
  private let device: DeviceDTO

  private var token: String?
  private var running = false
  private var runAgain = false
  private var lastSyncedAt: Date?

  /// Status changes, newest kept if nobody is reading. One consumer (the app's `SyncController`).
  public nonisolated let statusUpdates: AsyncStream<SyncStatus>
  private let statusContinuation: AsyncStream<SyncStatus>.Continuation

  /// - Parameters:
  ///   - session: the unlocked session `repository` was opened with -- the source of `k_auth`.
  ///   - device: this device as the server sees it; its `id` must be the repository's device id,
  ///     which stamps every local write.
  public init(
    api: any SyncAPI, repository: VaultRepository, session: VaultSession, device: DeviceDTO
  ) {
    self.api = api
    self.repository = repository
    self.session = session
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
        authKey: try await session.authKey(), device: device),
      enrollSecret: enrollSecret)
    try await repository.enableSync(
      SyncConfig(endpoint: endpoint, vaultID: vaultID, enabledAt: Date()),
      headerVersion: created.headerVersion)
    return vaultID
  }

  /// Record that this vault is `vaultID` on the server. The caller has already built the local
  /// vault from that server's header (`GET /header`, then unlock -- A.11 `join`); the next `run`
  /// pulls everything.
  public func join(endpoint: URL, vaultID: UUID, headerVersion: UInt64) async throws {
    try await repository.enableSync(
      SyncConfig(endpoint: endpoint, vaultID: vaultID, enabledAt: Date()),
      headerVersion: headerVersion)
  }

  // MARK: - Running

  /// Sync now. Single-flight: called while a run is in progress, it asks that run to go round
  /// once more when it finishes and returns at once.
  ///
  /// - Throws: the `SyncError` (or storage error) that stopped the run, after publishing it;
  ///   `CancellationError` if the calling task was cancelled -- the vault is consistent either
  ///   way.
  public func run() async throws {
    guard !running else {
      runAgain = true
      return
    }
    running = true
    defer { running = false }
    repeat {
      runAgain = false
      try await runOnce()
    } while runAgain
  }

  private func runOnce() async throws {
    do {
      guard let config = try await repository.syncConfig() else { throw SyncError.notEnabled }
      publish(.syncing(.connecting))
      token = nil
      _ = try await currentToken(config)

      var round = 0
      while true {
        publish(.syncing(.pulling))
        try await pull(config)
        publish(.syncing(.pushing))
        do {
          try await push(config)
          break
        } catch SyncError.conflicts(let conflicts) {
          // Someone pushed between our pull and our push: pull again, which reconciles them.
          round += 1
          if round >= Self.conflictRounds { throw SyncError.conflicts(conflicts) }
        }
      }

      publish(.syncing(.compacting))
      try await repository.compactSynced()
      token = nil
      lastSyncedAt = Date()
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
      SessionRequest(authKey: try await session.authKey(), device: device))
    guard opened.seq >= (try await repository.syncCursor()) else { throw SyncError.serverRollback }
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

  private func pull(_ config: SyncConfig) async throws {
    var cursor = try await repository.syncCursor()
    while true {
      let since = cursor
      let page = try await authorized(config) { token in
        try await self.api.changes(
          vaultID: config.vaultID, since: since, limit: Self.pageLimit, token: token)
      }
      guard page.seq >= cursor else { throw SyncError.serverRollback }
      guard let last = page.records.last else { return }
      // Ascending, after the cursor, within the server's own high-water mark, one entry per id.
      guard page.records.allSatisfy({ $0.seq > cursor && $0.seq <= page.seq }),
        zip(page.records, page.records.dropFirst()).allSatisfy({ $0.seq < $1.seq }),
        Set(page.records.map(\.id)).count == page.records.count
      else { throw SyncError.invalidResponse }

      try await ingest(page.records, cursor: last.seq)
      cursor = last.seq
      if !page.hasMore { return }
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
        return try await repository.applyRemote(plan, cursor: cursor)
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
