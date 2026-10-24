import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

/// `m5-sync.md` A.9 / Phase 10: what a hostile server can try, and how each is caught. Every case
/// ends with no silent acceptance, no local deletion, and every vault verifying.
@Suite struct SyncHostileServerTests {

  private func cursor(_ device: SyncDevice) async throws -> UInt64 {
    try await device.repo.syncCursor()
  }

  // MARK: - Rewinding seq: serverRollback

  @Test func aServerBehindTheCursorAtSessionStopsSync() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    _ = try await a.repo.create(AccountPayload(title: "one"))
    _ = try await a.repo.create(AccountPayload(title: "two"))
    try await a.engine.run()  // pushes
    try await a.engine.run()  // ingests the echoes: cursor 2
    #expect(try await cursor(a) == 2)

    await world.server.rewind(vaultID, seq: 1)
    let start = await world.server.calls.count
    await #expect(throws: SyncError.serverRollback) { try await a.engine.run() }
    #expect(await world.calls(from: start, .pull) == 0, "stopped at the session")
    #expect(try await cursor(a) == 2)
    try await world.verify(a)
  }

  @Test func aServerThatRewindsMidRunIsCaughtOnThePage() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    _ = try await a.repo.create(AccountPayload(title: "one"))
    _ = try await a.repo.create(AccountPayload(title: "two"))
    try await a.engine.run()
    try await a.engine.run()

    let server = world.server
    let once = Once()
    await server.setOnRequest { call in
      if call == .pull, once.claim() { await server.rewind(vaultID, seq: 1) }
    }
    await #expect(throws: SyncError.serverRollback) { try await a.engine.run() }
    #expect(try await cursor(a) == 2)
    #expect(try await a.repo.allAccounts().count == 2)
    try await world.verify(a)
  }

  // MARK: - Forging or altering a record: tamperedRecord, nothing applied

  @Test func aTamperedRecordRejectsTheWholePageOnAJoin() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    _ = try await a.repo.create(AccountPayload(title: "intact"))
    let forged = try await a.repo.create(AccountPayload(title: "tampered"))
    try await a.engine.run()

    await world.server.flipBit(vaultID, record: forged.id)
    let b = try await world.join("B", vaultID)
    await #expect(throws: SyncError.tamperedRecord(forged.id)) { try await b.engine.run() }
    #expect(try await b.repo.allAccounts().isEmpty, "nothing from the page was applied")
    #expect(try await cursor(b) == 0)
    try await world.verify(b)
  }

  @Test func aTamperedEditLeavesTheLocalRowsAsTheyWere() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let x = try await a.repo.create(AccountPayload(title: "X"))
    let y = try await a.repo.create(AccountPayload(title: "Y"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()
    let before = try await b.repo.allAccounts()
    let cursorBefore = try await cursor(b)

    _ = try await a.repo.update(id: x.id) { $0.notes = "edited" }
    _ = try await a.repo.update(id: y.id) { $0.notes = "edited" }
    try await a.engine.run()
    await world.server.flipBit(vaultID, record: x.id)

    await #expect(throws: SyncError.tamperedRecord(x.id)) { try await b.engine.run() }
    #expect(try await b.repo.allAccounts() == before, "Y's good edit in the same page waits too")
    #expect(try await cursor(b) == cursorBefore)
    try await world.verify(b)
  }

  // MARK: - Replaying an old version: ignored (rule 2)

  @Test func aReplayedOldVersionIsIgnored() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let x = try await a.repo.create(AccountPayload(title: "X", notes: "v1"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()
    _ = try await a.repo.update(id: x.id) { $0.notes = "v2" }
    try await a.engine.run()
    try await b.engine.run()

    await world.server.replayOldVersion(vaultID, record: x.id, version: 1)
    try await a.engine.run()
    try await b.engine.run()

    for device in [a, b] {
      let row = try #require(try await device.repo.account(id: x.id))
      #expect(row.version == 2)
      #expect(row.payload.notes == "v2")
      #expect(try await world.copies(of: x.id, on: device).isEmpty)
      #expect(try await device.repo.dirtyRecords().isEmpty)
      try await world.verify(device)
    }
    #expect(try await cursor(b) == (await world.server.vault(vaultID)?.seq), "ingested, ignored")
  }

  // MARK: - Dropping records: never deleted locally; re-uploaded on a resync

  @Test func aDroppedRecordStaysOnEveryDeviceAndComesBackOnAResync() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let x = try await a.repo.create(AccountPayload(title: "X"))
    _ = try await a.repo.create(AccountPayload(title: "Y"))
    try await a.engine.run()
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    await world.server.dropRecord(vaultID, record: x.id)
    let c = try await world.join("C", vaultID)
    try await c.engine.run()
    #expect(try await c.repo.account(id: x.id) == nil, "a new device can't get what was dropped")

    for device in [a, b] {
      try await device.engine.run()
      #expect(try await device.repo.account(id: x.id) != nil, "absence is not deletion")
    }

    // The server purges past A's cursor: A gets 410, resyncs, and uploads X again.
    let seq = try #require(await world.server.vault(vaultID)?.seq)
    await world.server.purge(vaultID, through: seq + 1)
    try await a.engine.run()
    #expect(await world.server.vault(vaultID)?.records[x.id] != nil)

    try await c.engine.run()
    #expect(try await c.repo.account(id: x.id)?.payload.title == "X")
    #expect(try await a.repo.allAccounts() == c.repo.allAccounts())
    for device in [a, b, c] { try await world.verify(device) }
  }

  // MARK: - Forging the header: the join fails at the unwrap, before any session

  @Test func aForgedHeaderFailsTheJoinBeforeAnythingIsSent() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    _ = try await a.repo.create(AccountPayload(title: "X"))
    try await a.engine.run()

    await world.server.forgeHeader(vaultID)
    let start = await world.server.calls.count
    await #expect(throws: PassFortError.authFailed) { _ = try await world.join("B", vaultID) }
    #expect(Array(await world.server.calls.dropFirst(start)) == [.header], "no session, no k_auth")
    #expect(!Vault.exists(databasePath: world.path("B")), "nothing written")
  }
}
