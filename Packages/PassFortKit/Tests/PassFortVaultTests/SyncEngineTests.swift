import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

/// `m5-sync.md` Phase 8's checkpoint, against `FakeSyncServer`: two vault files, two device ids,
/// one server -- and every scenario ends with both vaults verifying (manifest + mark).
@Suite struct SyncEngineTests {

  // MARK: - The checkpoint

  @Test func aJoiningDeviceReceivesEverything() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    for title in ["one", "two", "three"] {
      _ = try await a.repo.create(AccountPayload(title: title))
    }
    try await a.engine.run()

    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    #expect(try await b.repo.allAccounts().count == 3)
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
    #expect(try await a.repo.dirtyRecords().isEmpty)
    #expect(try await b.repo.dirtyRecords().isEmpty)
    #expect(await world.server.vault(vaultID)?.seq == 3)

    var updates = b.engine.statusUpdates.makeAsyncIterator()
    let status = await updates.next()
    guard case .idle(let at) = status else {
      Issue.record("expected idle, got \(String(describing: status))")
      return
    }
    #expect(at != nil)
    try await world.verify(a)
    try await world.verify(b)
  }

  @Test(arguments: ["A", "B"])
  func concurrentEditsEndWithTheClockWinnerAndOneCopyOnBoth(newer: String) async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let x = try await a.repo.create(AccountPayload(title: "X"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    // Both edit X offline; `newer` edits second.
    let (first, second) = newer == "B" ? (a, b) : (b, a)
    world.clock.advance()
    _ = try await first.repo.update(id: x.id) { $0.notes = "older" }
    world.clock.advance()
    _ = try await second.repo.update(id: x.id) { $0.notes = "newer" }

    try await a.engine.run()  // pushes X v2
    try await b.engine.run()  // conflicts, resolves, pushes
    try await a.engine.run()  // picks up the resolution

    for device in [a, b] {
      let winner = try #require(try await device.repo.account(id: x.id))
      #expect(winner.payload.notes == "newer")
      #expect(!winner.isDeleted)
      let copies = try await world.copies(of: x.id, on: device)
      #expect(copies.map(\.payload.notes) == ["older"])
      #expect(copies.first?.payload.revisionHistory.first?.changed == ["conflict copy"])
      #expect(try await device.repo.dirtyRecords().isEmpty)
      try await world.verify(device)
    }
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())

    // B won by re-sealing its edit above A's v2; A winning leaves A's v2 in place.
    let serverX = try #require(await world.server.vault(vaultID)?.records[x.id])
    #expect(serverX.version == (newer == "B" ? 3 : 2))
  }

  @Test(arguments: ["A", "B"])
  func aDeleteRacingAnEditKeepsTheEditAsACopy(syncsFirst: String) async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let y = try await a.repo.create(AccountPayload(title: "Y"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    world.clock.advance()
    _ = try await b.repo.update(id: y.id) { $0.notes = "B's edit" }
    world.clock.advance()
    try await a.repo.delete(id: y.id)  // the delete is newer: it wins

    let order = syncsFirst == "A" ? [a, b, a] : [b, a, b]
    for device in order { try await device.engine.run() }

    for device in [a, b] {
      #expect(try await device.repo.account(id: y.id)?.isDeleted ?? true, "the delete won")
      let copies = try await world.copies(of: y.id, on: device)
      #expect(copies.map(\.payload.notes) == ["B's edit"], "the edit survives")
      #expect(copies.allSatisfy { !$0.isDeleted })
      try await world.verify(device)
    }
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
  }

  @Test func anEditNewerThanADeleteBringsTheRecordBack() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let y = try await a.repo.create(AccountPayload(title: "Y"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    world.clock.advance()
    try await a.repo.delete(id: y.id)
    world.clock.advance()
    _ = try await b.repo.update(id: y.id) { $0.notes = "B's later edit" }

    for device in [a, b, a] { try await device.engine.run() }

    for device in [a, b] {
      let survivor = try #require(try await device.repo.account(id: y.id))
      #expect(!survivor.isDeleted)
      #expect(survivor.payload.notes == "B's later edit")
      #expect(
        try await world.copies(of: y.id, on: device).isEmpty, "a losing delete leaves nothing")
      try await world.verify(device)
    }
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
  }

  @Test func twoThousandRecordsSyncInPages() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    try await a.repo.importAccounts((0..<2_000).map { AccountPayload(title: "record \($0)") })

    var start = await world.server.calls.count
    try await a.engine.run()
    #expect(await world.calls(from: start, .push) == 21, "99 per batch")

    let b = try await world.join("B", vaultID)
    start = await world.server.calls.count
    try await b.engine.run()
    #expect(await world.calls(from: start, .pull) == 4, "500 per page")

    #expect(try await b.repo.allAccounts().count == 2_000)
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
    try await world.verify(a)
    try await world.verify(b)
  }

  @Test func cancellingAJoinsFirstPullLeavesTheVaultVerifyingAndTheNextRunRedoesIt()
    async throws
  {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    try await a.repo.importAccounts((0..<1_200).map { AccountPayload(title: "record \($0)") })
    try await a.engine.run()
    let b = try await world.join("B", vaultID)

    // Two pages land; the third pull is cancelled.
    let pulls = Counter()
    await world.server.setOnRequest { call in
      if call == .pull, pulls.increment() == 3 { withUnsafeCurrentTask { $0?.cancel() } }
    }
    let run = Task { try await b.engine.run() }
    await #expect(throws: CancellationError.self) { try await run.value }

    #expect(try await b.repo.allAccounts().count == 1_000)
    #expect(try await b.repo.syncCursor() == 0, "a full resync is finished or redone")
    try await world.verify(b)

    await world.server.setOnRequest(nil)
    try await b.engine.run()
    #expect(try await b.repo.syncCursor() == 1_200)
    #expect(try await b.repo.dirtyRecords().isEmpty, "the redo re-uploads nothing")
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
    try await world.verify(a)
    try await world.verify(b)
  }

  @Test func cancellingAnIncrementalPullKeepsThePagesThatLanded() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    _ = try await a.repo.create(AccountPayload(title: "first"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()  // cursor 1
    try await a.repo.importAccounts((0..<1_200).map { AccountPayload(title: "record \($0)") })
    try await a.engine.run()

    let pulls = Counter()
    await world.server.setOnRequest { call in
      if call == .pull, pulls.increment() == 3 { withUnsafeCurrentTask { $0?.cancel() } }
    }
    let run = Task { try await b.engine.run() }
    await #expect(throws: CancellationError.self) { try await run.value }

    #expect(try await b.repo.allAccounts().count == 1_001)
    #expect(try await b.repo.syncCursor() == 1_001, "each page committed with its cursor")
    try await world.verify(b)

    await world.server.setOnRequest(nil)
    try await b.engine.run()
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
    try await world.verify(b)
  }

  @Test func cancellingMidPushLeavesTheVaultVerifyingAndTheNextRunFinishes() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    try await a.repo.importAccounts((0..<300).map { AccountPayload(title: "record \($0)") })

    let pushes = Counter()
    await world.server.setOnRequest { call in
      if call == .push, pushes.increment() == 2 { withUnsafeCurrentTask { $0?.cancel() } }
    }
    let run = Task { try await a.engine.run() }
    await #expect(throws: CancellationError.self) { try await run.value }

    #expect(await world.server.vault(vaultID)?.records.count == 99)
    #expect(try await a.repo.dirtyRecords().count == 201)
    try await world.verify(a)

    await world.server.setOnRequest(nil)
    try await a.engine.run()
    #expect(await world.server.vault(vaultID)?.records.count == 300)
    #expect(try await a.repo.dirtyRecords().isEmpty)
    let b = try await world.join("B", vaultID)
    try await b.engine.run()
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
  }

  // MARK: - The run's edges

  @Test func aLostPushResponseIsReconciledWithoutACopy() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let x = try await a.repo.create(AccountPayload(title: "X"))

    await world.server.loseNextPushResponse()
    await #expect(throws: SyncError.offline) { try await a.engine.run() }
    #expect(try await a.repo.dirtyRecords().map(\.id) == [x.id], "the client never heard")

    // The echo is the same edit (rule 5a): taken, clean, nothing copied or pushed twice.
    try await a.engine.run()
    #expect(try await a.repo.dirtyRecords().isEmpty)
    #expect(try await a.repo.allAccounts().count == 1)
    #expect(await world.server.vault(vaultID)?.seq == 1)
    try await world.verify(a)
  }

  @Test func aPushThatLosesARacePullsAndTriesAgain() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let x = try await a.repo.create(AccountPayload(title: "X"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    world.clock.advance()
    _ = try await a.repo.update(id: x.id) { $0.notes = "A" }
    world.clock.advance()
    _ = try await b.repo.update(id: x.id) { $0.notes = "B" }

    // A pushes between B's pull and B's push: B's push is refused (409), B pulls and retries.
    let once = Once()
    await world.server.setOnRequest { call in
      if call == .push, once.claim() { try await a.engine.run() }
    }
    let start = await world.server.calls.count
    try await b.engine.run()
    await world.server.setOnRequest(nil)
    #expect(await world.calls(from: start, .pull) >= 3, "B pulled again after the 409")

    try await a.engine.run()
    for device in [a, b] {
      #expect(try await device.repo.account(id: x.id)?.payload.notes == "B")
      #expect(try await world.copies(of: x.id, on: device).map(\.payload.notes) == ["A"])
      try await world.verify(device)
    }
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
  }

  @Test func anExpiredTokenOpensANewSession() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    _ = try await a.repo.create(AccountPayload(title: "X"))

    let once = Once()
    let server = world.server
    await server.setOnRequest { call in
      if call == .push, once.claim() { await server.expireTokens() }
    }
    let start = await server.calls.count
    try await a.engine.run()
    #expect(await world.calls(from: start, .openSession) == 2)
    #expect(await server.vault(vaultID)?.records.count == 1)
  }

  @Test func aSecondRunRequestedMidRunGoesRoundAgain() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, _) = try await world.enableA()

    let once = Once()
    await world.server.setOnRequest { call in
      if call == .openSession, once.claim() { try await a.engine.run() }  // returns at once
    }
    let start = await world.server.calls.count
    try await a.engine.run()
    #expect(await world.calls(from: start, .openSession) == 2)
  }

  @Test func aVaultWithoutSyncConfigDoesNotRun() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let header = try VaultSession.create(password: world.password, params: SyncWorld.fastParams)
    let lone = try await world.makeDevice("lone", header: header)
    await #expect(throws: SyncError.notEnabled) { try await lone.engine.run() }
    #expect(await world.server.calls.isEmpty)
  }

  @Test func aLocalWriteAfterPlanningMakesTheIngestStale() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, _) = try await world.enableA()
    let x = try await a.repo.create(AccountPayload(title: "X"))

    let snapshot = try await a.repo.rowsForIngest([x.id])
    var plan = ReconcilePlan(vaultVersion: snapshot.vaultVersion)
    plan.rows = [try #require(snapshot.rows[x.id])]
    _ = try await a.repo.update(id: x.id) { $0.notes = "edited while the page was planned" }

    await #expect(throws: VaultError.staleWrite) { try await a.repo.applyRemote(plan, cursor: 9) }
    #expect(try await a.repo.syncCursor() == 0, "nothing from the stale plan landed")
    #expect(
      try await a.repo.account(id: x.id)?.payload.notes == "edited while the page was planned")
    try await world.verify(a)
  }

  // MARK: - What the CLI and the app read (Phase 11)

  @Test func aRunReportsWhatItDid() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let x = try await a.repo.create(AccountPayload(title: "X"))
    _ = try await a.repo.create(AccountPayload(title: "Y"))
    let first = try await a.engine.run()
    #expect(first.pushed == 2)
    #expect(first.pulled == 0)
    #expect(first.fullResync, "a first run from cursor 0")

    let b = try await world.join("B", vaultID)
    #expect(try await b.engine.run().pulled == 2)
    _ = try await a.repo.update(id: x.id) { $0.notes = "A" }
    _ = try await b.repo.update(id: x.id) { $0.notes = "B" }
    try await a.engine.run()
    let conflicted = try await b.engine.run()
    #expect(conflicted.conflictCopies == 1)
    #expect(conflicted.pushed == 2, "the resolution and the copy")
    #expect(!conflicted.fullResync)
  }

  @Test func theVaultVersionMovesWithRecordsNotWithEchoes() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    _ = try await a.repo.create(AccountPayload(title: "X"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    // A pulls its own push back: bookkeeping only.
    let before = try await a.repo.vaultVersion()
    #expect(try await a.engine.run().pulled == 1, "the echo")
    #expect(try await a.repo.vaultVersion() == before)

    // A record from another device moves it.
    _ = try await b.repo.create(AccountPayload(title: "From B"))
    try await b.engine.run()
    try await a.engine.run()
    #expect(try await a.repo.vaultVersion() > before)
  }

  @Test func syncStateTracksTheCursorTheQueueAndTheLastRun() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    _ = try await a.repo.create(AccountPayload(title: "X"))

    let before = try #require(try await a.repo.syncState())
    #expect(before.vaultID == vaultID)
    #expect(before.endpoint == SyncWorld.endpoint)
    #expect(before.dirtyCount == 1)
    #expect(before.cursor == 0)
    #expect(before.headerVersion == 1)
    #expect(before.lastSyncedAt == nil)

    try await a.engine.run()
    try await a.engine.run()
    let after = try #require(try await a.repo.syncState())
    #expect(after.dirtyCount == 0)
    #expect(after.cursor == 1)
    #expect(after.lastSyncedAt != nil)
  }

  @Test func devicesAreListedAndOneCanBeRemoved() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    #expect(Set(try await a.engine.devices().map(\.id)) == [a.id, b.id])
    try await a.engine.removeDevice(b.id)
    #expect(try await a.engine.devices().map(\.id) == [a.id])
    await #expect(throws: SyncError.notFound) { try await a.engine.removeDevice(b.id) }
  }

  @Test func disablingForgetsTheServerAndReEnablingUploadsEverything() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    _ = try await a.repo.create(AccountPayload(title: "X"))
    _ = try await a.repo.create(AccountPayload(title: "Y"))
    try await a.engine.run()

    try await a.engine.deleteServerCopy()
    #expect(await world.server.vault(vaultID) == nil)
    try await a.repo.disableSync()
    #expect(try await a.repo.syncState() == nil)
    #expect(try await a.repo.dirtyRecords().count == 2, "every row is unsynced again")
    #expect(try await a.repo.allAccounts().count == 2, "records untouched")
    await #expect(throws: SyncError.notEnabled) { try await a.engine.run() }
    try await world.verify(a)

    let fresh = try await a.engine.enable(endpoint: SyncWorld.endpoint, enrollSecret: "enroll")
    #expect(fresh != vaultID)
    #expect(try await a.engine.run().pushed == 2)
  }

  // MARK: - Batching

  @Test func batchesRespectTheRecordAndByteLimits() {
    let small = PushDTO(
      id: UUID(), baseVersion: 0, version: 1,
      hlc: HLCDTO(HLC(wallMillis: 1, counter: 0, deviceID: UUID())),
      sealed: Data(count: 256), isDeleted: false)
    #expect(SyncEngine.batches(Array(repeating: small, count: 199)).map(\.count) == [99, 99, 1])

    var big = small
    big.sealed = Data(count: 60_000)  // ~80 KB of base64: 38 fit under the budget
    let sizes = SyncEngine.batches(Array(repeating: big, count: 80)).map(\.count)
    #expect(sizes.reduce(0, +) == 80)
    #expect(sizes.allSatisfy { $0 * (80_000 + 400) <= SyncEngine.batchBytes })
    #expect(SyncEngine.batches([]).isEmpty)
  }
}
