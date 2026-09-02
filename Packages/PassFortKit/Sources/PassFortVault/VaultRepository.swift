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

  private init(
    database: VaultDatabase, session: VaultSession, deviceID: UUID, highWater: HighWaterMark,
    faultHook: FaultHook?
  ) {
    self.database = database
    self.session = session
    self.deviceID = deviceID
    self.highWater = highWater
    self.faultHook = faultHook
  }

  // MARK: - Lifecycle

  /// Initialise a brand-new vault: store the header blob, seed `vault_version = 0`
  /// and a manifest over the empty record set. `session` must already be open on
  /// `header`.
  public static func bootstrap(
    database: VaultDatabase, session: VaultSession, header: Data, deviceID: UUID,
    highWater: HighWaterMark, faultHook: FaultHook? = nil
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
      faultHook: faultHook)
  }

  /// Open an existing vault: verify the manifest and the anti-rollback mark
  /// (§5.5), then repair the sidecar forward if the file is ahead of it (a crash
  /// between a commit and its bump). Throws `VaultManifest.Failure` on tamper or
  /// rollback.
  public static func open(
    database: VaultDatabase, session: VaultSession, deviceID: UUID, highWater: HighWaterMark,
    faultHook: FaultHook? = nil
  ) async throws -> VaultRepository {
    let mark = try highWater.read()
    let state = try await VaultManifest.verifyAtUnlock(
      session: session, database: database, highWater: mark)
    if state.vaultVersion > mark { try highWater.write(state.vaultVersion) }
    return VaultRepository(
      database: database, session: session, deviceID: deviceID, highWater: highWater,
      faultHook: faultHook)
  }

  /// The stored header blob -- what the caller passed to `VaultSession.open` to get
  /// here, handed back for `pf_recovery_*` (Phase 8) and re-wrap flows.
  public func header() async throws -> Data {
    try await database.dbQueue.read { db in
      guard let header = try VaultMeta.read(db, .header) else { throw VaultError.notFound }
      return header
    }
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

  /// The secret-free in-memory index (§8.3): one `pf_open` per record, projected to
  /// `AccountSummary`. Includes tombstones (flagged). Rebuilt on every call; the
  /// caller holds it only while unlocked.
  public func summaries() async throws -> [AccountSummary] {
    let records = try await database.dbQueue.read { db in
      try SealedRecord.order(Column("uuid")).fetchAll(db)
    }
    var summaries: [AccountSummary] = []
    summaries.reserveCapacity(records.count)
    for record in records {
      summaries.append(Account(envelope: record, payload: try await decrypt(record)).summary)
    }
    return summaries
  }

  // MARK: - Writes

  /// Create a record at version 1. Seeds a `["created"]` revision entry and stamps
  /// `passwordChangedAt` if a password is present (§7.2).
  public func create(_ payload: AccountPayload) async throws -> Account {
    var payload = payload
    payload.schemaVersion = 1
    if payload.revisionHistory.isEmpty {
      payload.revisionHistory = [
        RevisionEntry(version: 1, at: payload.createdAt, changed: ["created"])
      ]
    }
    if payload.password?.isEmpty == false, payload.passwordChangedAt == nil {
      payload.passwordChangedAt = payload.createdAt
    }

    let id = UUID()
    let record = SealedRecord(
      id: id, version: 1, schemaVersion: 1,
      sealed: try await seal(id: id, version: 1, payload: payload),
      isDeleted: false, updatedAt: .now(device: deviceID))

    try await commit { db in try record.insert(db) }
    return Account(envelope: record, payload: payload)
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
    next.updatedAt = .now(device: deviceID)
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
    tombstone.updatedAt = .now(device: deviceID)
    Self.recordHistory(
      before: payload, into: &payload, version: tombstone.version, at: Date(), extra: "deleted")
    tombstone.sealed = try await seal(id: id, version: tombstone.version, payload: payload)

    let row = tombstone
    try await commit { db in try row.update(db) }
  }

  /// Purge tombstones. M2 has no sync, so "acked by every device" is just "deleted";
  /// M5 gates this on the sync cursor. A no-op (and no version bump) when there is
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
  private func commit(_ rowChange: @Sendable @escaping (Database) throws -> Void) async throws {
    let previous = try await database.dbQueue.read { db in try VaultMeta.readVaultVersion(db) }
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
