import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

/// `m5-sync.md` A.10 / Phase 10: tombstone purge, `410`, the full resync and its re-upload, and
/// how a restored backup comes back into step with the server.
@Suite struct SyncResyncTests {

  @Test func aRemovedDeviceThatSyncsAgainResyncsAndReuploads() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let y = try await a.repo.create(AccountPayload(title: "Y"))
    _ = try await a.repo.create(AccountPayload(title: "Z"))
    try await a.engine.run()
    try await a.engine.run()  // cursor 2
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    // A is removed; B deletes Y and syncs until the server purges the tombstone.
    await world.server.unregister(vaultID, device: a.id)
    try await b.repo.delete(id: y.id)
    for _ in 0..<4 { try await b.engine.run() }
    let server = try #require(await world.server.vault(vaultID))
    #expect(server.records[y.id] == nil, "purged: every registered device pulled past it")
    #expect(server.purgedThroughSeq == 3)
    #expect(try await b.repo.account(id: y.id) == nil, "B compacted its clean tombstone")

    // A's cursor (2) is behind the purge: 410, a full resync, and Y -- which A still has, live --
    // is uploaded again. The A.10 trade: a delete made while A was away can come back.
    let start = await world.server.calls.count
    try await a.engine.run()
    #expect(await world.calls(from: start, .pull) == 2, "the 410, then the pull from 0")
    #expect(try await a.repo.syncCursor() == 3, "finished at the purge mark")
    #expect(await world.server.vault(vaultID)?.records[y.id]?.isDeleted == false)

    let quiet = await world.server.calls.count
    try await a.engine.run()
    #expect(await world.calls(from: quiet, .pull) == 1, "back to incremental: no second resync")

    try await b.engine.run()
    #expect(try await b.repo.account(id: y.id)?.isDeleted == false)
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
    try await world.verify(a)
    try await world.verify(b)
  }

  @Test func aRestoredBackupCatchesUpWithNoSpuriousCopies() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let x = try await a.repo.create(AccountPayload(title: "X", notes: "one"))
    let kept = try await a.repo.create(AccountPayload(title: "unchanged"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    // The backup holds X dirty at v2 -- an edit not yet pushed when it was taken.
    _ = try await a.repo.update(id: x.id) { $0.notes = "two" }
    let backup = world.dir.appending(path: "a-backup.sqlite")
    _ = try VaultBackup.create(databasePath: a.path, to: backup)

    // Afterwards: v2 is pushed, A edits X again, B adds a record.
    try await a.engine.run()
    _ = try await a.repo.update(id: x.id) { $0.notes = "three" }
    try await a.engine.run()
    let z = try await b.repo.create(AccountPayload(title: "Z"))
    try await b.engine.run()

    try VaultBackup.restore(from: backup, toDatabasePath: a.path)
    await #expect(throws: VaultManifest.Failure.self) {
      _ = try await Vault.unlock(databasePath: a.path, password: world.password, deviceID: a.id)
    }
    try await Vault.acceptRestoredBackup(databasePath: a.path)
    let restored = try await world.unlock(a, password: world.password)
    #expect(try await restored.repo.syncCursor() == 0)
    #expect(try await restored.repo.account(id: x.id)?.payload.notes == "two")

    try await restored.engine.run()
    #expect(try await restored.repo.account(id: x.id)?.payload.notes == "three")
    #expect(try await restored.repo.account(id: z.id) != nil)
    #expect(try await restored.repo.account(id: kept.id) != nil)
    #expect(try await world.copies(of: x.id, on: restored).isEmpty, "v2 is an ancestor of v3")
    #expect(try await restored.repo.dirtyRecords().isEmpty)

    try await b.engine.run()
    #expect(try await restored.repo.allAccounts() == b.repo.allAccounts())
    try await world.verify(restored)
    try await world.verify(b)
  }

  @Test func acceptingARestoreWithSyncOffLeavesNoCursor() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let header = try VaultSession.create(password: world.password, params: SyncWorld.fastParams)
    let lone = try await world.makeDevice("lone", header: header)
    _ = try await lone.repo.create(AccountPayload(title: "X"))
    try await Vault.acceptRestoredBackup(databasePath: lone.path)
    let stored = try await VaultDatabase(path: lone.path).dbQueue.read { db in
      try VaultMeta.read(db, .syncCursor)
    }
    #expect(stored == nil)
    #expect(try HighWaterMark(sidecarFor: lone.path).read() == 0, "the mark was cleared")
  }

  @Test func aResyncAgainstAnEmptyServerUploadsEverythingAgain() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let ids = try await (0..<3).asyncMap {
      try await a.repo.create(AccountPayload(title: "\($0)")).id
    }
    try await a.engine.run()
    try await a.engine.run()
    for id in ids { await world.server.dropRecord(vaultID, record: id) }

    try await Vault.acceptRestoredBackup(databasePath: a.path)  // cursor back to 0
    try await a.engine.run()
    #expect(await world.server.vault(vaultID)?.records.count == 3)
    #expect(try await a.repo.dirtyRecords().isEmpty)
    try await world.verify(a)
  }
}

extension Sequence {
  fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
    var out: [T] = []
    for element in self { out.append(try await transform(element)) }
    return out
  }
}
