import Foundation
import PassFortCrypto
import PassFortVault
import Testing

@testable import PassFort

/// `m5-sync.md` Phase 13.2: `AppModel` and its `SyncController` against an in-memory server --
/// two "Macs" are two models on two vault files with two device identities.
@MainActor
struct AppModelSyncTests {
  private static let endpoint = URL(string: "http://localhost:7071/api/v1")!
  private let password = Data("correct horse".utf8)
  private let fastParams = KdfParameters(
    kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))

  private let server = MemorySyncServer()
  private let dir: URL

  init() throws {
    dir = FileManager.default.temporaryDirectory.appending(path: "pf-appsync-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  private func path(_ name: String) -> String {
    dir.appending(path: "\(name).sqlite").path(percentEncoded: false)
  }

  private func model(_ name: String) -> AppModel {
    let server = self.server
    return AppModel(
      databasePath: path(name), syncAPI: { _ in server },
      device: DeviceIdentity(id: UUID(), name: name))
  }

  /// Mac A: a new vault, unlocked, sync on, everything uploaded.
  private func enabledA() async throws -> (model: AppModel, vaultID: UUID) {
    _ = try await Vault.create(
      databasePath: path("A"), password: password, params: fastParams, deviceID: UUID())
    let a = model("A")
    await a.unlock(password: password)
    let sync = try #require(a.sync)
    #expect(sync.status == .off)
    let vaultID = try await sync.enable(
      endpoint: Self.endpoint, enrollSecret: MemorySyncServer.enrollSecret)
    await sync.syncNow()
    return (a, vaultID)
  }

  // MARK: - Enable and join

  @Test func joinBootstrapsAndPulls() async throws {
    defer { try? FileManager.default.removeItem(at: dir) }
    let (a, vaultID) = try await enabledA()
    #expect(await a.createAccount(AccountPayload(title: "GitHub")) == nil)
    await a.sync?.syncNow()
    #expect(await server.recordCount(vaultID) == 1)

    let b = model("B")
    #expect(b.state == .needsVault)
    #expect(await b.joinVault(endpoint: Self.endpoint, vaultID: vaultID, password: password) == nil)
    #expect(b.state == .unlocked)
    await b.sync?.syncNow()

    #expect(b.summaries.map(\.title) == ["GitHub"])
    #expect(b.sync?.state?.vaultID == vaultID)
    if case .idle(let last) = b.sync?.status { #expect(last != nil) } else {
      Issue.record("expected idle, got \(String(describing: b.sync?.status))")
    }
  }

  @Test func joiningWithTheWrongPasswordLeavesNothingBehind() async throws {
    defer { try? FileManager.default.removeItem(at: dir) }
    let (_, vaultID) = try await enabledA()

    let b = model("B")
    let failure = await b.joinVault(
      endpoint: Self.endpoint, vaultID: vaultID, password: Data("wrong".utf8))
    #expect(failure == .wrongPassword)
    #expect(b.state == .needsVault)
    #expect(!Vault.exists(databasePath: path("B")))
  }

  @Test func anEditOnOneMacReachesTheOther() async throws {
    defer { try? FileManager.default.removeItem(at: dir) }
    let (a, vaultID) = try await enabledA()
    let b = model("B")
    _ = await b.joinVault(endpoint: Self.endpoint, vaultID: vaultID, password: password)
    await b.sync?.syncNow()

    #expect(await b.createAccount(AccountPayload(title: "From B")) == nil)
    await b.sync?.syncNow()
    let before = a.writeCounter
    await a.sync?.syncNow()

    #expect(a.summaries.map(\.title) == ["From B"])
    #expect(a.writeCounter != before, "an open detail view re-decrypts")
  }

  // MARK: - Conflicts

  @Test func conflictCopyAppearsInSummaries() async throws {
    defer { try? FileManager.default.removeItem(at: dir) }
    let (a, vaultID) = try await enabledA()
    _ = await a.createAccount(AccountPayload(title: "Email", password: "one"))
    await a.sync?.syncNow()
    let b = model("B")
    _ = await b.joinVault(endpoint: Self.endpoint, vaultID: vaultID, password: password)
    await b.sync?.syncNow()
    let id = try #require(a.summaries.first?.id)

    // Both edit offline; whichever the clock prefers wins, the other becomes the copy.
    await server.setOnRequest { _ in throw SyncError.offline }
    _ = await a.updateAccount(id: id, to: AccountPayload(title: "Email", password: "A's"))
    try await Task.sleep(for: .milliseconds(5))
    _ = await b.updateAccount(id: id, to: AccountPayload(title: "Email", password: "B's"))
    await a.sync?.syncNow()
    #expect(a.sync?.status == .offline)
    await server.setOnRequest(nil)
    for model in [a, b, a] { await model.sync?.syncNow() }

    for model in [a, b] {
      #expect(model.summaries.count == 2)
      #expect(model.conflictSummaries.count == 1)
    }

    let copy = try #require(a.conflictSummaries.first)
    #expect(await a.resolveConflict(copy: copy.id, .keepBoth) == nil)
    for model in [a, b] { await model.sync?.syncNow() }
    #expect(a.conflictSummaries.isEmpty)
    #expect(b.conflictSummaries.isEmpty)
  }

  // MARK: - Failures and locking

  @Test func syncErrorDoesNotLockOrDropTheSession() async throws {
    defer { try? FileManager.default.removeItem(at: dir) }
    let (a, _) = try await enabledA()

    await server.setOnRequest { _ in throw SyncError.server(status: 500, retryAfter: nil) }
    await a.sync?.syncNow()
    #expect(a.state == .unlocked)
    #expect(a.repo != nil)
    #expect(a.sync?.status == .problem(.server(status: 500, retryAfter: nil)))
    #expect(a.sync?.isPaused == false, "a server error only holds automatic runs off")
    #expect(await a.createAccount(AccountPayload(title: "Still works")) == nil)

    await server.setOnRequest { _ in throw SyncError.pinningFailed }
    await a.sync?.syncNow()
    #expect(a.sync?.isPaused == true)
    #expect(a.state == .unlocked)

    await server.setOnRequest(nil)
    await a.sync?.syncNow()
    #expect(a.sync?.isPaused == false)
    #expect(a.sync?.state?.dirtyCount == 0)
  }

  @Test func lockCancelsSync() async throws {
    defer { try? FileManager.default.removeItem(at: dir) }
    let (a, _) = try await enabledA()
    _ = await a.createAccount(AccountPayload(title: "Pending"))
    a.lock()

    // The run that starts at unlock hangs on its pull until it is cancelled.
    let entered = AsyncStream.makeStream(of: Void.self)
    await server.setOnRequest { call in
      guard call == .pull else { return }
      entered.continuation.yield()
      try await Task.sleep(for: .seconds(30))
    }
    await a.unlock(password: password)
    var iterator = entered.stream.makeAsyncIterator()
    _ = await iterator.next()

    weak let released = a.repo
    a.lock()
    #expect(a.sync == nil)
    for _ in 0..<100 where released != nil { try await Task.sleep(for: .milliseconds(20)) }
    #expect(released == nil, "the cancelled run let go of the vault")

    await server.setOnRequest(nil)
    await a.unlock(password: password)
    #expect(a.state == .unlocked, "the vault unlocks and verifies")
    await a.sync?.syncNow()
    #expect(a.sync?.state?.dirtyCount == 0)
  }

  // MARK: - More than one vault

  @Test func joiningInPlaceSetsTheOpenVaultAsideAndKeepsItsSync() async throws {
    defer { try? FileManager.default.removeItem(at: dir) }
    let (a, firstVault) = try await enabledA()
    _ = await a.createAccount(AccountPayload(title: "In the first vault"))
    await a.sync?.syncNow()

    // A second vault, put on the same server by another Mac.
    _ = try await Vault.create(
      databasePath: path("C"), password: password, params: fastParams, deviceID: UUID())
    let c = model("C")
    await c.unlock(password: password)
    let secondVault = try #require(
      try await c.sync?.enable(
        endpoint: Self.endpoint, enrollSecret: MemorySyncServer.enrollSecret))
    _ = await c.createAccount(AccountPayload(title: "In the second vault"))
    await c.sync?.syncNow()
    #expect(Set(await server.vaultIDs) == [firstVault, secondVault])

    let result = await a.joinVaultInPlace(
      endpoint: Self.endpoint, vaultID: secondVault, password: password)
    let keptAt = try result.get()
    await a.sync?.syncNow()
    #expect(a.summaries.map(\.title) == ["In the second vault"])
    #expect(a.sync?.state?.vaultID == secondVault)

    // The set-aside file still carries the first vault's sync settings.
    let kept = try await Vault.unlock(databasePath: keptAt, password: password, deviceID: UUID())
    #expect(try await kept.syncState()?.vaultID == firstVault)
  }

  @Test func aFailedJoinInPlacePutsTheOpenVaultBack() async throws {
    defer { try? FileManager.default.removeItem(at: dir) }
    let (a, vaultID) = try await enabledA()
    _ = await a.createAccount(AccountPayload(title: "Mine"))

    let result = await a.joinVaultInPlace(
      endpoint: Self.endpoint, vaultID: vaultID, password: Data("wrong".utf8))
    #expect(throws: AppError.wrongPassword) { try result.get() }
    await a.unlock(password: password)
    #expect(a.summaries.map(\.title) == ["Mine"])
  }
}
