import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

/// A wall clock a test moves by hand, shared by every device in it -- so "B edited later" is a
/// fact of the test, not of the machine's timing.
final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: UInt64 = 1_800_000_000_000

  var now: UInt64 { lock.withLock { value } }
  func advance(_ millis: UInt64 = 1_000) { lock.withLock { value += millis } }
  var wallClock: WallClock { WallClock { self.now } }
}

/// Set once, read many: a hook's "only the first time".
final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var fired = false

  /// True the first time only.
  func claim() -> Bool {
    lock.withLock {
      defer { fired = true }
      return !fired
    }
  }
}

/// `m5-sync.md` Phase 8's checkpoint, against `FakeSyncServer`: two vault files, two device ids,
/// one server -- and every scenario ends with both vaults verifying (manifest + mark).
@Suite struct SyncEngineTests {

  private static let endpoint = URL(string: "http://localhost:7071/api/v1")!
  private let password = Data("correct horse".utf8)
  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }

  private struct World {
    let server = FakeSyncServer()
    let clock = TestClock()
    let dir: URL

    init() throws {
      dir = FileManager.default.temporaryDirectory.appending(path: "pf-engine-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: dir) }
  }

  private struct Device {
    let id: UUID
    let path: String
    let header: Data
    let repo: VaultRepository
    let engine: SyncEngine
  }

  private func makeDevice(_ name: String, header: Data, in world: World) async throws -> Device {
    let id = UUID()
    let path = world.dir.appending(path: "\(name).sqlite").path(percentEncoded: false)
    let session = try VaultSession.open(header: header, password: password)
    let repo = try await VaultRepository.bootstrap(
      database: try VaultDatabase(path: path), session: session, header: header, deviceID: id,
      highWater: HighWaterMark(sidecarFor: path), wallClock: world.clock.wallClock)
    let engine = SyncEngine(
      api: world.server, repository: repo, session: session,
      device: DeviceDTO(id: id, name: name, platform: .cli))
    return Device(id: id, path: path, header: header, repo: repo, engine: engine)
  }

  /// Device A: a brand-new vault, put on the server.
  private func enableA(in world: World) async throws -> (device: Device, vaultID: UUID) {
    let header = try VaultSession.create(password: password, params: fastParams)
    let a = try await makeDevice("A", header: header, in: world)
    let vaultID = try await a.engine.enable(endpoint: Self.endpoint, enrollSecret: "enroll")
    return (a, vaultID)
  }

  /// Another device joins: an empty vault built on the server's header.
  private func join(_ name: String, _ vaultID: UUID, in world: World) async throws -> Device {
    let fetched = try await world.server.header(vaultID: vaultID)
    let device = try await makeDevice(name, header: fetched.header, in: world)
    try await device.engine.join(
      endpoint: Self.endpoint, vaultID: vaultID, headerVersion: fetched.headerVersion)
    return device
  }

  /// Reopen from disk: the manifest MAC and the anti-rollback mark must both verify.
  private func verify(_ device: Device) async throws {
    _ = try await VaultRepository.open(
      database: try VaultDatabase(path: device.path),
      session: try VaultSession.open(header: device.header, password: password),
      deviceID: device.id, highWater: HighWaterMark(sidecarFor: device.path))
  }

  private func copies(of id: UUID, on device: Device) async throws -> [Account] {
    try await device.repo.allAccounts().filter { $0.payload.conflictOf == id }
  }

  private func calls(_ server: FakeSyncServer, from start: Int, _ call: FakeSyncServer.Call)
    async -> Int
  {
    await server.calls.dropFirst(start).filter { $0 == call }.count
  }

  // MARK: - The checkpoint

  @Test func aJoiningDeviceReceivesEverything() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    for title in ["one", "two", "three"] {
      _ = try await a.repo.create(AccountPayload(title: title))
    }
    try await a.engine.run()

    let b = try await join("B", vaultID, in: world)
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
    try await verify(a)
    try await verify(b)
  }

  @Test(arguments: ["A", "B"])
  func concurrentEditsEndWithTheClockWinnerAndOneCopyOnBoth(newer: String) async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    let x = try await a.repo.create(AccountPayload(title: "X"))
    try await a.engine.run()
    let b = try await join("B", vaultID, in: world)
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
      let copies = try await copies(of: x.id, on: device)
      #expect(copies.map(\.payload.notes) == ["older"])
      #expect(copies.first?.payload.revisionHistory.first?.changed == ["conflict copy"])
      #expect(try await device.repo.dirtyRecords().isEmpty)
      try await verify(device)
    }
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())

    // B won by re-sealing its edit above A's v2; A winning leaves A's v2 in place.
    let serverX = try #require(await world.server.vault(vaultID)?.records[x.id])
    #expect(serverX.version == (newer == "B" ? 3 : 2))
  }

  @Test(arguments: ["A", "B"])
  func aDeleteRacingAnEditKeepsTheEditAsACopy(syncsFirst: String) async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    let y = try await a.repo.create(AccountPayload(title: "Y"))
    try await a.engine.run()
    let b = try await join("B", vaultID, in: world)
    try await b.engine.run()

    world.clock.advance()
    _ = try await b.repo.update(id: y.id) { $0.notes = "B's edit" }
    world.clock.advance()
    try await a.repo.delete(id: y.id)  // the delete is newer: it wins

    let order = syncsFirst == "A" ? [a, b, a] : [b, a, b]
    for device in order { try await device.engine.run() }

    for device in [a, b] {
      #expect(try await device.repo.account(id: y.id)?.isDeleted ?? true, "the delete won")
      let copies = try await copies(of: y.id, on: device)
      #expect(copies.map(\.payload.notes) == ["B's edit"], "the edit survives")
      #expect(copies.allSatisfy { !$0.isDeleted })
      try await verify(device)
    }
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
  }

  @Test func anEditNewerThanADeleteBringsTheRecordBack() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    let y = try await a.repo.create(AccountPayload(title: "Y"))
    try await a.engine.run()
    let b = try await join("B", vaultID, in: world)
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
      #expect(try await copies(of: y.id, on: device).isEmpty, "a losing delete leaves nothing")
      try await verify(device)
    }
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
  }

  @Test func twoThousandRecordsSyncInPages() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    try await a.repo.importAccounts((0..<2_000).map { AccountPayload(title: "record \($0)") })

    var start = await world.server.calls.count
    try await a.engine.run()
    #expect(await calls(world.server, from: start, .push) == 21, "99 per batch")

    let b = try await join("B", vaultID, in: world)
    start = await world.server.calls.count
    try await b.engine.run()
    #expect(await calls(world.server, from: start, .pull) == 4, "500 per page")

    #expect(try await b.repo.allAccounts().count == 2_000)
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
    try await verify(a)
    try await verify(b)
  }

  @Test func cancellingMidPullLeavesTheVaultVerifyingAndTheNextRunResumes() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    try await a.repo.importAccounts((0..<1_200).map { AccountPayload(title: "record \($0)") })
    try await a.engine.run()
    let b = try await join("B", vaultID, in: world)

    // Two pages land; the third pull is cancelled.
    let pulls = Counter()
    await world.server.setOnRequest { call in
      if call == .pull, pulls.increment() == 3 { withUnsafeCurrentTask { $0?.cancel() } }
    }
    let run = Task { try await b.engine.run() }
    await #expect(throws: CancellationError.self) { try await run.value }

    #expect(try await b.repo.allAccounts().count == 1_000)
    #expect(try await b.repo.syncCursor() == 1_000)
    try await verify(b)

    await world.server.setOnRequest(nil)
    try await b.engine.run()
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
    try await verify(a)
    try await verify(b)
  }

  @Test func cancellingMidPushLeavesTheVaultVerifyingAndTheNextRunFinishes() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    try await a.repo.importAccounts((0..<300).map { AccountPayload(title: "record \($0)") })

    let pushes = Counter()
    await world.server.setOnRequest { call in
      if call == .push, pushes.increment() == 2 { withUnsafeCurrentTask { $0?.cancel() } }
    }
    let run = Task { try await a.engine.run() }
    await #expect(throws: CancellationError.self) { try await run.value }

    #expect(await world.server.vault(vaultID)?.records.count == 99)
    #expect(try await a.repo.dirtyRecords().count == 201)
    try await verify(a)

    await world.server.setOnRequest(nil)
    try await a.engine.run()
    #expect(await world.server.vault(vaultID)?.records.count == 300)
    #expect(try await a.repo.dirtyRecords().isEmpty)
    let b = try await join("B", vaultID, in: world)
    try await b.engine.run()
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
  }

  // MARK: - The run's edges

  @Test func aLostPushResponseIsReconciledWithoutACopy() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    let x = try await a.repo.create(AccountPayload(title: "X"))

    await world.server.loseNextPushResponse()
    await #expect(throws: SyncError.offline) { try await a.engine.run() }
    #expect(try await a.repo.dirtyRecords().map(\.id) == [x.id], "the client never heard")

    // The echo is the same edit (rule 5a): taken, clean, nothing copied or pushed twice.
    try await a.engine.run()
    #expect(try await a.repo.dirtyRecords().isEmpty)
    #expect(try await a.repo.allAccounts().count == 1)
    #expect(await world.server.vault(vaultID)?.seq == 1)
    try await verify(a)
  }

  @Test func aPushThatLosesARacePullsAndTriesAgain() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    let x = try await a.repo.create(AccountPayload(title: "X"))
    try await a.engine.run()
    let b = try await join("B", vaultID, in: world)
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
    #expect(await calls(world.server, from: start, .pull) >= 3, "B pulled again after the 409")

    try await a.engine.run()
    for device in [a, b] {
      #expect(try await device.repo.account(id: x.id)?.payload.notes == "B")
      #expect(try await copies(of: x.id, on: device).map(\.payload.notes) == ["A"])
      try await verify(device)
    }
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
  }

  @Test func anExpiredTokenOpensANewSession() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    _ = try await a.repo.create(AccountPayload(title: "X"))

    let once = Once()
    let server = world.server
    await server.setOnRequest { call in
      if call == .push, once.claim() { await server.expireTokens() }
    }
    let start = await server.calls.count
    try await a.engine.run()
    #expect(await calls(server, from: start, .openSession) == 2)
    #expect(await server.vault(vaultID)?.records.count == 1)
  }

  @Test func aSecondRunRequestedMidRunGoesRoundAgain() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, _) = try await enableA(in: world)

    let once = Once()
    await world.server.setOnRequest { call in
      if call == .openSession, once.claim() { try await a.engine.run() }  // returns at once
    }
    let start = await world.server.calls.count
    try await a.engine.run()
    #expect(await calls(world.server, from: start, .openSession) == 2)
  }

  @Test func aServerBehindTheCursorStopsSync() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    _ = try await a.repo.create(AccountPayload(title: "one"))
    _ = try await a.repo.create(AccountPayload(title: "two"))
    try await a.engine.run()  // pushes
    try await a.engine.run()  // ingests the echoes: cursor 2
    #expect(try await a.repo.syncCursor() == 2)

    await world.server.rewind(vaultID, seq: 1)
    await #expect(throws: SyncError.serverRollback) { try await a.engine.run() }
    try await verify(a)
  }

  @Test func aTamperedRecordRejectsTheWholePage() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, vaultID) = try await enableA(in: world)
    _ = try await a.repo.create(AccountPayload(title: "intact"))
    let forged = try await a.repo.create(AccountPayload(title: "tampered"))
    try await a.engine.run()

    await world.server.flipBit(vaultID, record: forged.id)
    let b = try await join("B", vaultID, in: world)
    await #expect(throws: SyncError.tamperedRecord(forged.id)) { try await b.engine.run() }
    #expect(try await b.repo.allAccounts().isEmpty, "nothing from the page was applied")
    #expect(try await b.repo.syncCursor() == 0)
    try await verify(b)
  }

  @Test func aVaultWithoutSyncConfigDoesNotRun() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let header = try VaultSession.create(password: password, params: fastParams)
    let lone = try await makeDevice("lone", header: header, in: world)
    await #expect(throws: SyncError.notEnabled) { try await lone.engine.run() }
    #expect(await world.server.calls.isEmpty)
  }

  @Test func aLocalWriteAfterPlanningMakesTheIngestStale() async throws {
    let world = try World()
    defer { world.cleanUp() }
    let (a, _) = try await enableA(in: world)
    let x = try await a.repo.create(AccountPayload(title: "X"))

    let snapshot = try await a.repo.rowsForIngest([x.id])
    var plan = ReconcilePlan(vaultVersion: snapshot.vaultVersion)
    plan.rows = [try #require(snapshot.rows[x.id])]
    _ = try await a.repo.update(id: x.id) { $0.notes = "edited while the page was planned" }

    await #expect(throws: VaultError.staleWrite) { try await a.repo.applyRemote(plan, cursor: 9) }
    #expect(try await a.repo.syncCursor() == 0, "nothing from the stale plan landed")
    #expect(
      try await a.repo.account(id: x.id)?.payload.notes == "edited while the page was planned")
    try await verify(a)
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

/// A thread-safe counter for request hooks.
final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  /// The count after this call.
  func increment() -> Int {
    lock.withLock {
      value += 1
      return value
    }
  }
}
