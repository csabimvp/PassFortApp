import Foundation
import GRDB
import PassFortCrypto

public enum VaultError: Error, Equatable {
  /// No live record with that id (a tombstone counts as not found for reads).
  case notFound
  /// `vault_version` moved under us between reading it and the write transaction
  /// -- another writer got in first. Retry.
  case staleWrite
  /// `Vault.create` was called on a database that already holds a vault header.
  case alreadyInitialized
  /// `ExportConfirmation` was built with the wrong phrase.
  case exportNotConfirmed
}

/// A crash-injection point in the write path, for the §8.2 mid-write kill test
/// (Phase 7). A `FaultHook` is called at each point and may `_exit` the process;
/// it is `nil` in every normal build and reachable only by the code that
/// constructs the repository, so it is inert in production.
public enum FaultPoint: String, Sendable, CaseIterable {
  /// Inside the transaction, the row is written, the manifest is not.
  case afterRowWrite
  /// Inside the transaction, `manifest_mac` and `vault_version` are both written
  /// -- but not yet committed.
  case afterMetaWrite
  /// The transaction has committed; the sidecar high-water mark is not yet bumped.
  case afterCommit
}

public typealias FaultHook = @Sendable (FaultPoint) -> Void

/// One record the sync server accepted in a push: the version it stored and the `seq` it gave
/// it (`m5-sync.md` A.3 `applied`).
public struct PushedRecord: Sendable, Equatable {
  public var id: UUID
  public var version: UInt64
  public var seq: UInt64

  public init(id: UUID, version: UInt64, seq: UInt64) {
    self.id = id
    self.version = version
    self.seq = seq
  }
}

/// The one place the §8.2 invariant lives: **every write is a single transaction
/// covering the row *and* the manifest MAC**. `VaultRepository` is an `actor`, so
/// its own calls serialize; the `DatabaseQueue` underneath serializes SQLite; and
/// the manifest recompute happens inside the same `write { }` block as the row
/// change, so there is no code path where one lands without the other.
///
/// It cannot import `PFCrypto` (§4) -- it goes through `VaultSession` /
/// `ManifestBuilder` for every crypto operation and never sees a key.
public actor VaultRepository {
  private let database: VaultDatabase
  private let session: VaultSession
  private let deviceID: UUID
  private let highWater: HighWaterMark
  private let faultHook: FaultHook?
  /// Stamps every write (A.5): seeded with the vault's newest stamp, so it never goes backwards.
  /// A sync run feeds every pulled stamp through it (`receive`).
  let clock: HLCClock

  private init(
    database: VaultDatabase, session: VaultSession, deviceID: UUID, highWater: HighWaterMark,
    faultHook: FaultHook?, clock: HLCClock
  ) {
    self.database = database
    self.session = session
    self.deviceID = deviceID
    self.highWater = highWater
    self.faultHook = faultHook
    self.clock = clock
  }

  // MARK: - Lifecycle

  /// Initialise a brand-new vault: store the header blob, seed `vault_version = 0`
  /// and a manifest over the empty record set. `session` must already be open on
  /// `header`. `wallClock` is what the HLC reads; tests freeze it.
  public static func bootstrap(
    database: VaultDatabase, session: VaultSession, header: Data, deviceID: UUID,
    highWater: HighWaterMark, faultHook: FaultHook? = nil, wallClock: WallClock = .system
  ) async throws -> VaultRepository {
    let builder = try await session.makeManifestBuilder(vaultVersion: 0)
    try await database.dbQueue.write { db in
      try VaultMeta.write(db, .header, header)
      let mac = try builder.finish()  // no rows to fold yet
      try VaultMeta.write(db, .manifestMAC, mac)
      try VaultMeta.writeVaultVersion(db, 0)
    }
    try highWater.write(0)
    return VaultRepository(
      database: database, session: session, deviceID: deviceID, highWater: highWater,
      faultHook: faultHook,
      clock: HLCClock(deviceID: deviceID, seed: nil, wallClock: wallClock))
  }

  /// Open an existing vault: verify the manifest and the anti-rollback mark
  /// (§5.5), then repair the sidecar forward if the file is ahead of it (a crash
  /// between a commit and its bump). Throws `VaultManifest.Failure` on tamper or
  /// rollback.
  public static func open(
    database: VaultDatabase, session: VaultSession, deviceID: UUID, highWater: HighWaterMark,
    faultHook: FaultHook? = nil, wallClock: WallClock = .system
  ) async throws -> VaultRepository {
    let mark = try highWater.read()
    let state = try await VaultManifest.verifyAtUnlock(
      session: session, database: database, highWater: mark)
    if state.vaultVersion > mark { try highWater.write(state.vaultVersion) }
    let newest = try await database.dbQueue.read { db in try newestStamp(db) }
    return VaultRepository(
      database: database, session: session, deviceID: deviceID, highWater: highWater,
      faultHook: faultHook,
      clock: HLCClock(deviceID: deviceID, seed: newest, wallClock: wallClock))
  }

  /// The newest HLC in the vault by (wall, counter) -- the clock's seed. `nil` when empty.
  private static func newestStamp(_ db: Database) throws -> HLC? {
    try SealedRecord
      .order(Column("updated_at").desc, Column("hlc_counter").desc)
      .fetchOne(db)?.updatedAt
  }

  /// The stored header blob -- what the caller passed to `VaultSession.open` to get
  /// here, handed back for `pf_recovery_*` (Phase 8) and re-wrap flows.
  public func header() async throws -> Data {
    try await database.dbQueue.read { db in
      guard let header = try VaultMeta.read(db, .header) else { throw VaultError.notFound }
      return header
    }
  }

  /// The plaintext §5.3 vault id -- what `VaultImport` compares to refuse importing a vault into
  /// itself.
  func vaultUUID() async throws -> UUID {
    try await session.vaultUUID()
  }

  /// Replace the vault's recovery slot with a fresh key -- or add one if there is
  /// none (§5.6). Rewrites the stored header; the DEK, records and manifest are
  /// untouched, so `vault_version` does not move. The returned `RecoveryKey` is
  /// shown once and never stored.
  public func rotateRecoveryKey() async throws -> RecoveryKey {
    let recovery = RecoveryKey.generate()
    let newHeader = try await session.addRecoverySlot(recoveryKey: recovery.raw)
    try await database.dbQueue.write { db in try VaultMeta.write(db, .header, newHeader) }
    return recovery
  }

  /// Change the master password: verify `current` against the stored header, then
  /// re-wrap the same DEK under `new` (same KDF cost, fresh salt). Records and the
  /// manifest are untouched, so `vault_version` does not move.
  ///
  /// A recovery slot cannot survive the re-wrap -- its AEAD tag covers the header
  /// prefix, salt included -- so any existing recovery key stops working. With
  /// `issueRecoveryKey`, a fresh slot is added in the same header write and its key
  /// returned (shown once, never stored); without it the vault ends up password-only.
  ///
  /// - Throws: `PassFortError.authFailed` if `current` is wrong; the header is then
  ///   unchanged.
  public func changePassword(
    current: Data, new: Data, issueRecoveryKey: Bool
  ) async throws -> RecoveryKey? {
    // A second Argon2 pass against the stored header -- the session can't check a
    // password itself, and must not hand back the KEK to compare against.
    _ = try VaultSession.open(header: try await header(), password: current)

    var newHeader = try await session.rewrap(newPassword: new)
    var recovery: RecoveryKey?
    if issueRecoveryKey {
      let key = RecoveryKey.generate()
      newHeader = try await session.addRecoverySlot(recoveryKey: key.raw)
      recovery = key
    }
    let header = newHeader
    try await database.dbQueue.write { db in try VaultMeta.write(db, .header, header) }
    return recovery
  }

  // MARK: - Reads

  /// One decrypted account, or `nil` if there is no such row. A tombstone is
  /// returned with `isDeleted == true` rather than hidden -- the caller decides.
  public func account(id: UUID) async throws -> Account? {
    guard
      let record = try await database.dbQueue.read({ db in
        try SealedRecord.fetchOne(db, key: id.rawData)
      })
    else { return nil }
    return Account(envelope: record, payload: try await decrypt(record))
  }

  /// The escape hatch (§7.6): every record decrypted into a `PlaintextExport`.
  /// Gated on `ExportConfirmation` so it cannot run by accident. Includes
  /// tombstones. The result is plaintext secrets -- the caller writes it `0600`.
  public func exportPlaintext(confirmed: ExportConfirmation) async throws -> PlaintextExport {
    _ = confirmed  // its construction was the gate
    let vaultUUID = try await session.vaultUUID()
    let records = try await database.dbQueue.read { db in
      try SealedRecord.order(Column("uuid")).fetchAll(db)
    }
    var accounts: [ExportedAccount] = []
    accounts.reserveCapacity(records.count)
    for record in records {
      accounts.append(
        ExportedAccount(
          id: record.id, version: record.version,
          updatedAt: Date(timeIntervalSince1970: Double(record.updatedAt.wallMillis) / 1000),
          isDeleted: record.isDeleted, payload: try await decrypt(record)))
    }
    return PlaintextExport(
      schemaVersion: 1, exportedAt: Date(), vaultUUID: vaultUUID, accounts: accounts)
  }

  /// Every record, decrypted -- tombstones included. Internal on purpose: whole-vault plaintext
  /// stays inside the actor, and only derived, secret-free results (`summaries`, `audit`) go out.
  /// `exportPlaintext` is the one gated exception.
  func allAccounts() async throws -> [Account] {
    let records = try await database.dbQueue.read { db in
      try SealedRecord.order(Column("uuid")).fetchAll(db)
    }
    var accounts: [Account] = []
    accounts.reserveCapacity(records.count)
    for record in records {
      accounts.append(Account(envelope: record, payload: try await decrypt(record)))
    }
    return accounts
  }

  /// The secret-free in-memory index (§8.3): one `pf_open` per record, projected to
  /// `AccountSummary`. Includes tombstones (flagged). Rebuilt on every call; the
  /// caller holds it only while unlocked.
  public func summaries() async throws -> [AccountSummary] {
    try await allAccounts().map(\.summary)
  }

  // MARK: - Writes

  /// Create a record at version 1. Seeds a `["created"]` revision entry and stamps
  /// `passwordChangedAt` if a password is present (§7.2).
  public func create(_ payload: AccountPayload) async throws -> Account {
    let (record, sealedPayload) = try await newRecord(
      payload, origin: "created", at: payload.createdAt)
    try await commit { db in try record.insert(db) }
    return Account(envelope: record, payload: sealedPayload)
  }

  /// Create many records in **one** transaction -- all of them or none, and one manifest re-MAC
  /// instead of one per record (§8.2). Each gets an `["imported"]` revision entry stamped now,
  /// whatever its `createdAt`. Returns the count written.
  @discardableResult
  public func importAccounts(_ payloads: [AccountPayload]) async throws -> Int {
    guard !payloads.isEmpty else { return 0 }
    let now = Date()
    var records: [SealedRecord] = []
    records.reserveCapacity(payloads.count)
    for payload in payloads {
      records.append(try await newRecord(payload, origin: "imported", at: now).record)
    }
    let rows = records
    try await commit { db in
      for row in rows { try row.insert(db) }
    }
    return rows.count
  }

  /// A sealed version-1 record for `payload`, with its first revision entry (`origin`) and
  /// `passwordChangedAt` defaulted to `createdAt`.
  private func newRecord(
    _ payload: AccountPayload, origin: String, at: Date
  ) async throws -> (record: SealedRecord, payload: AccountPayload) {
    var payload = payload
    payload.schemaVersion = 1
    if payload.revisionHistory.isEmpty {
      payload.revisionHistory = [RevisionEntry(version: 1, at: at, changed: [origin])]
    }
    if payload.password?.isEmpty == false, payload.passwordChangedAt == nil {
      payload.passwordChangedAt = payload.createdAt
    }

    let id = UUID()
    let record = SealedRecord(
      id: id, version: 1, schemaVersion: 1,
      sealed: try await seal(id: id, version: 1, payload: payload),
      isDeleted: false, updatedAt: await clock.tick())
    return (record, payload)
  }

  /// Decrypt, apply `mutate`, bump `version`, restamp `updatedAt`, record what
  /// changed (§7.2), re-seal, write -- the row change and the manifest re-MAC in
  /// one transaction.
  @discardableResult
  public func update(
    id: UUID, _ mutate: @Sendable (inout AccountPayload) -> Void
  ) async throws -> Account {
    let current = try await liveRecord(id)
    var payload = try await decrypt(current)
    let before = payload
    mutate(&payload)

    var next = current
    next.version += 1
    next.updatedAt = await clock.tick()
    Self.recordHistory(before: before, into: &payload, version: next.version, at: Date())
    next.sealed = try await seal(id: id, version: next.version, payload: payload)

    let row = next
    try await commit { db in try row.update(db) }
    return Account(envelope: next, payload: payload)
  }

  /// Tombstone a record: `is_deleted = 1`, `version` bumped, payload re-sealed at
  /// the new version so the row and its blob stay consistent and the transition is
  /// covered by the manifest (via the version bump -- `is_deleted` itself is *not*
  /// in the MAC, §5.5). The row survives until `compact`. Records a `["deleted"]`
  /// revision entry.
  public func delete(id: UUID) async throws {
    let current = try await liveRecord(id)
    var payload = try await decrypt(current)

    var tombstone = current
    tombstone.isDeleted = true
    tombstone.version += 1
    tombstone.updatedAt = await clock.tick()
    Self.recordHistory(
      before: payload, into: &payload, version: tombstone.version, at: Date(), extra: "deleted")
    tombstone.sealed = try await seal(id: id, version: tombstone.version, payload: payload)

    let row = tombstone
    try await commit { db in try row.update(db) }
  }

  /// Undo a `delete`: clear `is_deleted`, bump `version`, re-seal at the new version, and record a
  /// `["restored"]` revision -- through the same one-transaction path as every write (§8.2). Under
  /// sync (M5) this is an ordinary newer version, so it propagates like an edit.
  ///
  /// - Throws: `VaultError.notFound` if there is no such row or it is not deleted.
  @discardableResult
  public func restore(id: UUID) async throws -> Account {
    let current = try await database.dbQueue.read { db in
      try SealedRecord.fetchOne(db, key: id.rawData)
    }
    guard let current, current.isDeleted else { throw VaultError.notFound }
    var payload = try await decrypt(current)

    var next = current
    next.isDeleted = false
    next.version += 1
    next.updatedAt = await clock.tick()
    Self.recordHistory(
      before: payload, into: &payload, version: next.version, at: Date(), extra: "restored")
    next.sealed = try await seal(id: id, version: next.version, payload: payload)

    let row = next
    try await commit { db in try row.update(db) }
    return Account(envelope: next, payload: payload)
  }

  /// Purge tombstones -- with sync off, where "acked by every device" is just "deleted". With
  /// sync on, `compactSynced` is the one to call. A no-op (and no version bump) when there is
  /// nothing to purge.
  public func compact() async throws {
    let tombstones = try await database.dbQueue.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM records WHERE is_deleted = 1") ?? 0
    }
    guard tombstones > 0 else { return }
    try await commit { db in
      try db.execute(sql: "DELETE FROM records WHERE is_deleted = 1")
    }
  }

  // MARK: - Sync bookkeeping (A.5)

  /// Every row the server doesn't have at its current version -- never pushed, or changed since
  /// the last push -- tombstones included, in UUID order. What the next push sends, each with
  /// `baseVersion = syncedVersion ?? 0`.
  public func dirtyRecords() async throws -> [SealedRecord] {
    try await database.dbQueue.read { db in
      try SealedRecord
        .filter(sql: "synced_version IS NULL OR synced_version != version")
        .order(Column("uuid"))
        .fetchAll(db)
    }
  }

  /// Record what a push stored: `synced_version` / `synced_seq` per accepted record. A plain
  /// transaction, not `commit`: these columns are bookkeeping outside the manifest MAC (§5.5),
  /// so `vault_version` doesn't move. A row edited again since the push (a higher `version`)
  /// still records the pushed version -- it stays dirty, and its next push names the right base.
  /// A row the push no longer matches (gone, or behind the pushed version) is left alone.
  public func markPushed(_ applied: [PushedRecord]) async throws {
    guard !applied.isEmpty else { return }
    try await database.dbQueue.write { db in try Self.markSynced(db, applied) }
  }

  /// `markPushed`'s update, shared with an ingest's echo confirmations.
  private static func markSynced(_ db: Database, _ records: [PushedRecord]) throws {
    for record in records {
      try db.execute(
        sql: """
          UPDATE records SET synced_version = ?, synced_seq = ?
          WHERE uuid = ? AND version >= ?
          """,
        arguments: [
          Int64(bitPattern: record.version), Int64(bitPattern: record.seq), record.id.rawData,
          Int64(bitPattern: record.version),
        ])
    }
  }

  /// Purge the tombstones the server already has (A.10) -- with sync on, other devices learn of
  /// a delete from the server, not from this vault. A dirty tombstone stays until it is pushed.
  /// One `commit`, like every row change; a no-op when there is nothing clean to purge.
  public func compactSynced() async throws {
    let clean = "is_deleted = 1 AND synced_version = version"
    let count = try await database.dbQueue.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM records WHERE \(clean)") ?? 0
    }
    guard count > 0 else { return }
    try await commit { db in
      try db.execute(sql: "DELETE FROM records WHERE \(clean)")
    }
  }

  // MARK: - Ingest (A.6, A.7)

  /// Write one reconciled page and move `sync_cursor` to `cursor` -- the generalised `commit`:
  /// every row and conflict copy, the manifest re-MAC, `vault_version` and the cursor in ONE
  /// transaction, or nothing (§8.2). A page of echoes only moves bookkeeping outside the MAC
  /// (`synced_*`, the cursor), so it takes a plain transaction instead and `vault_version` stays.
  ///
  /// - Throws: `VaultError.staleWrite` if a local write landed after `plan` was built -- plan the
  ///   page again against the new rows.
  public func applyRemote(_ plan: ReconcilePlan, cursor: UInt64) async throws {
    guard !plan.isBookkeepingOnly else {
      try await database.dbQueue.write { db in
        try Self.markSynced(db, plan.confirmations)
        try VaultMeta.writeSyncCursor(db, cursor)
      }
      return
    }
    try await commit(basedOn: plan.vaultVersion) { db in
      for row in plan.rows + plan.conflictCopies { try row.save(db) }
      try Self.markSynced(db, plan.confirmations)
      try VaultMeta.writeSyncCursor(db, cursor)
    }
  }

  /// The local rows a page lands on, keyed by id, and the `vault_version` they were read at --
  /// one snapshot, so a plan built from them can be checked for staleness.
  func rowsForIngest(_ ids: [UUID]) async throws -> (
    vaultVersion: UInt64, rows: [UUID: SealedRecord]
  ) {
    try await database.dbQueue.read { db in
      let rows = try SealedRecord.fetchAll(db, keys: ids.map(\.rawData))
      return (
        try VaultMeta.readVaultVersion(db),
        Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      )
    }
  }

  /// Decrypt a stored row -- the local side of a rule-5 conflict.
  func payload(of record: SealedRecord) async throws -> AccountPayload {
    try await decrypt(record)
  }

  /// Decrypt a pulled record against its own id and version. Fails exactly as a tampered blob
  /// does (`pf_open` binds both into the AAD, §5.4), which is how a forged or swapped record is
  /// caught before anything is written (A.9).
  func payload(of remote: RecordDTO) async throws -> AccountPayload {
    try await decrypt(SealedRecord(remote))
  }

  /// Rule 5c: `local`'s payload re-sealed at `version` -- the AEAD binds the version (§5.4), so
  /// the winner can't move above the server's version without a new seal. Keeps its own stamp:
  /// it is still the newer edit.
  func resealed(_ local: SealedRecord, payload: AccountPayload, at version: UInt64) async throws
    -> SealedRecord
  {
    var row = local
    row.version = version
    row.sealed = try await seal(id: local.id, version: version, payload: payload)
    return row
  }

  /// A conflict copy (A.7): a new record holding the losing side's payload, `conflictOf` the
  /// original, a `["conflict copy"]` revision entry, version 1, stamped now. Never synced yet, so
  /// the next push uploads it and every device gets it.
  func conflictCopy(of original: UUID, payload: AccountPayload) async throws -> SealedRecord {
    var payload = payload
    payload.conflictOf = original
    payload.revisionHistory.insert(
      RevisionEntry(version: 1, at: Date(), changed: ["conflict copy"]), at: 0)
    payload.revisionHistory = Array(payload.revisionHistory.prefix(Self.revisionHistoryLimit))

    let id = UUID()
    return SealedRecord(
      id: id, version: 1, schemaVersion: 1,
      sealed: try await seal(id: id, version: 1, payload: payload),
      isDeleted: false, updatedAt: await clock.tick())
  }

  // MARK: - Sync state (A.5)

  func syncConfig() async throws -> SyncConfig? {
    try await database.dbQueue.read { db in try VaultMeta.readSyncConfig(db) }
  }

  func syncCursor() async throws -> UInt64 {
    try await database.dbQueue.read { db in try VaultMeta.readSyncCursor(db) }
  }

  /// Turn sync on: where to, and the server header version this vault's header corresponds to.
  /// The cursor starts at 0 -- the first run pulls everything and pushes every (dirty) row.
  func enableSync(_ config: SyncConfig, headerVersion: UInt64) async throws {
    try await database.dbQueue.write { db in
      try VaultMeta.writeSyncConfig(db, config)
      try VaultMeta.writeSyncHeaderVersion(db, headerVersion)
      try VaultMeta.writeSyncCursor(db, 0)
    }
  }

  // MARK: - History (§7.2 / §7.7)

  /// Kept-password / revision-entry caps. Both arrays grow slowly (a password
  /// change / any edit that changes something), so the caps are generous; they
  /// exist so a script hammering one record can't unbound the sealed payload.
  /// `public` so the CLI / GUI can say "keeps the last N".
  public static let passwordHistoryLimit = 24
  public static let revisionHistoryLimit = 50

  /// The field **names** that differ between two payload versions -- never the
  /// values. Ordering is stable (declaration order) so a test can assert on it.
  /// Audit/derived fields (`strength`, `breach`, the history arrays themselves,
  /// `usedAt`, `unknown`) are deliberately excluded.
  static func changedFields(from old: AccountPayload, to new: AccountPayload) -> [String] {
    var changed: [String] = []
    func mark(_ name: String, _ differs: Bool) { if differs { changed.append(name) } }
    mark("title", old.title != new.title)
    mark("username", old.username != new.username)
    mark("password", old.password != new.password)
    mark("email", old.email != new.email)
    mark("notes", old.notes != new.notes)
    mark("urls", old.urls != new.urls)
    mark("totp", old.totp != new.totp)
    mark("security questions", old.securityQuestions != new.securityQuestions)
    mark("memorable word", old.memorableWord != new.memorableWord)
    mark("pin", old.pin != new.pin)
    mark("recovery codes", old.recoveryCodes != new.recoveryCodes)
    mark("expiry", old.expiresAt != new.expiresAt)
    mark("category", old.category != new.category)
    mark("tags", old.tags != new.tags)
    mark("favorite", old.favorite != new.favorite)
    mark("icon", old.iconHint != new.iconHint)
    mark("custom fields", old.customFields != new.customFields)
    return changed
  }

  /// Fold history into `payload` in place: keep the previous password value (if it
  /// changed and there was one), stamp `passwordChangedAt`, and prepend a revision
  /// entry naming what changed. Newest-first, both capped. A genuine no-op edit
  /// (nothing changed, no `extra`) records nothing.
  static func recordHistory(
    before: AccountPayload, into payload: inout AccountPayload, version: UInt64, at now: Date,
    extra: String? = nil
  ) {
    if before.password != payload.password {
      if let old = before.password, !old.isEmpty {
        payload.passwordHistory.insert(
          PasswordHistoryEntry(password: old, replacedAt: now), at: 0)
        payload.passwordHistory = Array(payload.passwordHistory.prefix(passwordHistoryLimit))
      }
      if payload.password?.isEmpty == false { payload.passwordChangedAt = now }
    }

    var changed = changedFields(from: before, to: payload)
    if let extra { changed.append(extra) }
    guard !changed.isEmpty else { return }

    payload.revisionHistory.insert(
      RevisionEntry(version: version, at: now, changed: changed), at: 0)
    payload.revisionHistory = Array(payload.revisionHistory.prefix(revisionHistoryLimit))
  }

  // MARK: - The §8.2 core

  /// Run `rowChange` and re-MAC the whole vault in ONE transaction, then bump the
  /// sidecar *after* the commit (bumping it first, then rolling back, would make
  /// the next unlock see `vault_version` < mark and refuse a good vault). The
  /// `ManifestBuilder` is opened before the transaction -- that is the one actor
  /// hop; folding rows through it inside the closure is synchronous.
  ///
  /// `basedOn` is the `vault_version` the change was computed against, when that was read
  /// earlier than this call (a sync ingest); a write in between makes it `staleWrite`.
  private func commit(
    basedOn expected: UInt64? = nil, _ rowChange: @Sendable @escaping (Database) throws -> Void
  ) async throws {
    let previous: UInt64
    if let expected {
      previous = expected
    } else {
      previous = try await database.dbQueue.read { db in try VaultMeta.readVaultVersion(db) }
    }
    let next = previous + 1
    let builder = try await session.makeManifestBuilder(vaultVersion: next)
    let fault = faultHook

    try await database.dbQueue.write { db in
      guard try VaultMeta.readVaultVersion(db) == previous else { throw VaultError.staleWrite }
      try rowChange(db)
      fault?(.afterRowWrite)
      for record in try SealedRecord.order(Column("uuid")).fetchAll(db) {
        try builder.update(recordID: record.id, version: record.version, sealed: record.sealed)
      }
      let mac = try builder.finish()
      try VaultMeta.write(db, .manifestMAC, mac)
      try VaultMeta.writeVaultVersion(db, next)
      fault?(.afterMetaWrite)
    }

    faultHook?(.afterCommit)
    try highWater.write(next)
  }

  // MARK: - Stats

  /// Crypto op counts since this session was opened — a UI "under the hood"
  /// panel (not a security property, and not persisted across unlocks).
  public struct CryptoStats: Sendable, Equatable {
    public let sealCount: UInt64
    public let openCount: UInt64
  }

  public func cryptoStats() async -> CryptoStats {
    let s = await session.cryptoStats()
    return CryptoStats(sealCount: s.sealCount, openCount: s.openCount)
  }

  // MARK: - Crypto helpers

  private func liveRecord(_ id: UUID) async throws -> SealedRecord {
    let record = try await database.dbQueue.read { db in
      try SealedRecord.fetchOne(db, key: id.rawData)
    }
    guard let record, !record.isDeleted else { throw VaultError.notFound }
    return record
  }

  private func decrypt(_ record: SealedRecord) async throws -> AccountPayload {
    try PayloadCodec.decode(
      try await session.open(
        recordID: record.id, version: record.version, schema: record.schemaVersion,
        sealed: record.sealed))
  }

  private func seal(id: UUID, version: UInt64, payload: AccountPayload) async throws -> Data {
    try await session.seal(
      recordID: id, version: version, schema: 1, plaintext: try PayloadCodec.encode(payload))
  }
}
