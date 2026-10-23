import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

/// The local half of sync that exists before any network (m5-sync.md Phase 6): HLC stamps on
/// every write, dirty tracking, `markPushed`, `compactSynced` and the `vault_meta` sync keys.
@Suite struct SyncBookkeepingTests {

  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }

  private let device = UUID(uuid: (9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9))
  /// A wall clock stuck at one instant: every stamp must still be strictly newer than the last.
  private let frozen = WallClock { 1_800_000_000_000 }

  private struct Harness {
    let dir: URL
    let path: String
    let header: Data
    let password: Data
    let repo: VaultRepository

    var database: VaultDatabase { get throws { try VaultDatabase(path: path) } }
  }

  private func makeHarness(wallClock: WallClock = .system) async throws -> Harness {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-sync-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appending(path: "vault.sqlite").path(percentEncoded: false)
    let password = Data("correct horse".utf8)
    let header = try VaultSession.create(password: password, params: fastParams)
    let repo = try await VaultRepository.bootstrap(
      database: try VaultDatabase(path: path),
      session: try VaultSession.open(header: header, password: password), header: header,
      deviceID: device, highWater: HighWaterMark(sidecarFor: path), wallClock: wallClock)
    return Harness(dir: dir, path: path, header: header, password: password, repo: repo)
  }

  private func reopen(_ h: Harness, wallClock: WallClock = .system) async throws
    -> VaultRepository
  {
    try await VaultRepository.open(
      database: try h.database, session: try VaultSession.open(header: h.header, password: h.password),
      deviceID: device, highWater: HighWaterMark(sidecarFor: h.path), wallClock: wallClock)
  }

  // MARK: - HLC stamps

  @Test func everyWriteIsStampedStrictlyNewerEvenWithAFrozenClock() async throws {
    let h = try await makeHarness(wallClock: frozen)
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "A"))
    let once = try await h.repo.update(id: made.id) { $0.notes = "one" }
    let twice = try await h.repo.update(id: made.id) { $0.notes = "two" }
    try await h.repo.delete(id: made.id)
    let deleted = try #require(try await h.repo.account(id: made.id))
    let restored = try await h.repo.restore(id: made.id)

    let stamps = [made.updatedAt, once.updatedAt, twice.updatedAt, deleted.updatedAt, restored.updatedAt]
    for (earlier, later) in zip(stamps, stamps.dropFirst()) { #expect(earlier < later) }
    #expect(stamps.allSatisfy { $0.wallMillis == 1_800_000_000_000 && $0.deviceID == device })
    #expect(stamps.map(\.counter) == [0, 1, 2, 3, 4])
  }

  @Test func theFullHLCRoundTripsThroughTheDatabase() async throws {
    let h = try await makeHarness(wallClock: frozen)
    defer { try? FileManager.default.removeItem(at: h.dir) }
    let made = try await h.repo.create(AccountPayload(title: "A"))
    let edited = try await h.repo.update(id: made.id) { $0.notes = "x" }

    let reread = try #require(try await reopen(h).account(id: made.id))
    #expect(reread.updatedAt == edited.updatedAt)
    #expect(reread.updatedAt.counter == 1)
    #expect(reread.updatedAt.deviceID == device)
  }

  @Test func aReopenedVaultKeepsCountingFromItsNewestStamp() async throws {
    let h = try await makeHarness(wallClock: frozen)
    defer { try? FileManager.default.removeItem(at: h.dir) }
    let made = try await h.repo.create(AccountPayload(title: "A"))
    let last = try await h.repo.update(id: made.id) { $0.notes = "x" }  // (frozen, 1)

    // This machine's clock is now behind what the vault holds.
    let behind = WallClock { 1_700_000_000_000 }
    let edited = try await reopen(h, wallClock: behind).update(id: made.id) { $0.notes = "y" }
    #expect(edited.updatedAt > last.updatedAt)
    #expect(edited.updatedAt.counter == 2)
  }

  // MARK: - Dirty tracking

  @Test func aNewRecordIsDirtyUntilPushedAndAnEditMakesItDirtyAgain() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    let a = try await h.repo.create(AccountPayload(title: "A"))
    let b = try await h.repo.create(AccountPayload(title: "B"))
    #expect(Set(try await h.repo.dirtyRecords().map(\.id)) == [a.id, b.id])

    try await h.repo.markPushed([PushedRecord(id: a.id, version: 1, seq: 7)])
    let afterPush = try await h.repo.dirtyRecords()
    #expect(afterPush.map(\.id) == [b.id])

    _ = try await h.repo.update(id: a.id) { $0.notes = "edited after the push" }
    let dirtyA = try #require(try await h.repo.dirtyRecords().first { $0.id == a.id })
    #expect(dirtyA.version == 2)
    #expect(dirtyA.syncedVersion == 1, "the next push's baseVersion")
    #expect(dirtyA.syncedSeq == 7)
  }

  @Test func markPushedKeepsTheBaseWhenTheRowMovedOnDuringThePush() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    let a = try await h.repo.create(AccountPayload(title: "A"))
    _ = try await h.repo.update(id: a.id) { $0.notes = "edited while version 1 was in flight" }

    try await h.repo.markPushed([PushedRecord(id: a.id, version: 1, seq: 3)])
    let row = try #require(try await h.repo.dirtyRecords().first)
    #expect(row.version == 2)
    #expect(row.syncedVersion == 1)
    #expect(row.isDirty)

    // A confirmation for a version the row never reached is ignored.
    try await h.repo.markPushed([PushedRecord(id: a.id, version: 9, seq: 4)])
    #expect(try await h.repo.dirtyRecords().first?.syncedVersion == 1)
  }

  @Test func markPushedLeavesTheManifestAndVaultVersionAlone() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    let a = try await h.repo.create(AccountPayload(title: "A"))
    let before = try await h.database.dbQueue.read { db in try VaultMeta.readVaultVersion(db) }

    try await h.repo.markPushed([PushedRecord(id: a.id, version: 1, seq: 1)])
    #expect(try await h.database.dbQueue.read { db in try VaultMeta.readVaultVersion(db) } == before)
    _ = try await reopen(h)  // the manifest still verifies: sync columns are outside the MAC
  }

  // MARK: - compactSynced

  @Test func compactSyncedPurgesOnlyTombstonesTheServerHas() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    let pushedThenDeleted = try await h.repo.create(AccountPayload(title: "clean tombstone"))
    let neverPushed = try await h.repo.create(AccountPayload(title: "dirty tombstone"))
    let live = try await h.repo.create(AccountPayload(title: "live"))
    try await h.repo.delete(id: pushedThenDeleted.id)
    try await h.repo.delete(id: neverPushed.id)
    try await h.repo.markPushed([
      PushedRecord(id: pushedThenDeleted.id, version: 2, seq: 4),
      PushedRecord(id: live.id, version: 1, seq: 5),
    ])

    try await h.repo.compactSynced()
    #expect(try await h.repo.account(id: pushedThenDeleted.id) == nil)
    #expect(try await h.repo.account(id: neverPushed.id)?.isDeleted == true, "not pushed yet")
    #expect(try await h.repo.account(id: live.id) != nil)
    _ = try await reopen(h)  // the purge went through `commit`: the manifest still verifies
  }

  @Test func compactSyncedWithNothingCleanDoesNotWrite() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    let a = try await h.repo.create(AccountPayload(title: "A"))
    try await h.repo.delete(id: a.id)
    let before = try await h.database.dbQueue.read { db in try VaultMeta.readVaultVersion(db) }
    try await h.repo.compactSynced()
    #expect(try await h.database.dbQueue.read { db in try VaultMeta.readVaultVersion(db) } == before)
  }

  // MARK: - vault_meta sync keys

  @Test func theSyncKeysRoundTripAndDefaultSensibly() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    let queue = try h.database.dbQueue

    try await queue.read { (db: Database) throws in
      #expect(try VaultMeta.readSyncConfig(db) == nil, "absent = sync off")
      #expect(try VaultMeta.readSyncCursor(db) == 0)
      #expect(try VaultMeta.readSyncHeaderVersion(db) == nil)
      #expect(try VaultMeta.readHeaderDirty(db) == false)
      #expect(try VaultMeta.readPendingHeader(db) == nil)
    }

    let config = SyncConfig(
      endpoint: URL(string: "https://example.azurestaticapps.net/api/v1")!,
      vaultID: UUID(), enabledAt: Date(timeIntervalSince1970: 1_800_000_000))
    let pending = PendingHeader(headerVersion: 3, header: Data(repeating: 0xAB, count: 133))
    try await queue.write { db in
      try VaultMeta.writeSyncConfig(db, config)
      try VaultMeta.writeSyncCursor(db, 0x0102_0304_0506_0708)
      try VaultMeta.writeSyncHeaderVersion(db, 2)
      try VaultMeta.writeHeaderDirty(db, true)
      try VaultMeta.writePendingHeader(db, pending)
    }
    try await queue.read { (db: Database) throws in
      #expect(try VaultMeta.readSyncConfig(db) == config)
      #expect(try VaultMeta.readSyncCursor(db) == 0x0102_0304_0506_0708)
      #expect(try VaultMeta.read(db, .syncCursor) == Data([1, 2, 3, 4, 5, 6, 7, 8]), "u64 BE")
      #expect(try VaultMeta.readSyncHeaderVersion(db) == 2)
      #expect(try VaultMeta.readHeaderDirty(db))
      #expect(try VaultMeta.readPendingHeader(db) == pending)
      let json = try #require(try VaultMeta.read(db, .syncConfig))
      #expect(String(decoding: json, as: UTF8.self).contains("\"vaultId\""))
    }

    try await queue.write { db in
      try VaultMeta.writeHeaderDirty(db, false)
      try VaultMeta.writePendingHeader(db, nil)
    }
    try await queue.read { (db: Database) throws in
      #expect(try VaultMeta.read(db, .headerDirty) == nil)
      #expect(try VaultMeta.readPendingHeader(db) == nil)
    }
  }
}
