import Foundation
import PassFortCrypto
import PassFortVault
import Testing

@testable import PassFort

/// Moving the vault end to end, with real vaults, real bookmarks and temp directories standing in
/// for "the app's storage" and "a folder the user chose".
@MainActor
struct VaultLocationModelTests {

  private let params = KdfParameters(
    kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  private let password = Data("correct horse".utf8)

  private final class MemoryStore: VaultLocationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var record: VaultLocationRecord?
    func load() -> VaultLocationRecord? { lock.withLock { record } }
    func save(_ record: VaultLocationRecord?) { lock.withLock { self.record = record } }
  }

  private struct FakeChecker: FolderChecking {
    var problem: LocationProblem?
    func problem(with folder: URL) -> LocationProblem? { problem }
  }

  private final class Recorder {
    var events: [String] = []
    var refusal: String?
    var hooks: VaultLocationModel.Hooks {
      VaultLocationModel.Hooks(
        begin: { [self] in
          events.append("begin")
          return refusal
        },
        releaseVault: { [self] in events.append("release") },
        abandon: { [self] in events.append("abandon") })
    }
  }

  private struct Fixture {
    let root: URL
    let support: URL
    let defaultPath: String
    let chosen: URL
    let store: MemoryStore
    let recorder: Recorder

    var chosenPath: String { VaultLocation.databasePath(inChosenFolder: chosen) }
    var customMark: URL { VaultLocation.customHighWaterURL(supportDirectory: support) }

    @MainActor func model(
      _ resolution: VaultLocation.Resolution = .standard, checker: FakeChecker = FakeChecker()
    ) -> VaultLocationModel {
      VaultLocationModel(
        resolution: resolution, store: store, checker: checker, supportDirectory: support,
        defaultDatabasePath: defaultPath)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
  }

  private func makeFixture() throws -> Fixture {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "pf-lm-\(UUID().uuidString)", directoryHint: .isDirectory)
    let support = root.appending(path: "support", directoryHint: .isDirectory)
    let chosen = root.appending(path: "chosen", directoryHint: .isDirectory)
    for dir in [support, chosen] {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return Fixture(
      root: root, support: support,
      defaultPath: root.appending(path: "default/vault.sqlite").path(percentEncoded: false),
      chosen: chosen, store: MemoryStore(), recorder: Recorder())
  }

  private func makeVault(at path: String, mark: URL? = nil, accounts: Int) async throws {
    let repo = try await Vault.create(
      databasePath: path, password: password, params: params, deviceID: VaultService.deviceID,
      highWater: mark.map(HighWaterMark.init(url:)))
    for i in 0..<accounts {
      _ = try await repo.create(AccountPayload(title: "acct-\(i)", username: "u", password: "p"))
    }
  }

  private func count(at path: String, mark: URL? = nil) async throws -> Int {
    try await Vault.unlock(
      databasePath: path, password: password, deviceID: VaultService.deviceID,
      highWater: mark.map(HighWaterMark.init(url:))
    ).summaries().filter { !$0.isDeleted }.count
  }

  private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

  // MARK: - What each resolution means for the rest of the app

  @Test func eachResolutionMapsToPathsAndMarks() throws {
    let f = try makeFixture()
    defer { f.remove() }

    let standard = f.model(.standard)
    #expect(standard.databasePath == f.defaultPath)
    #expect(standard.highWaterURL == nil)  // the sidecar beside the vault, as always
    #expect(standard.isUsable && !standard.isCustom)

    let custom = f.model(.custom(.init(folder: f.chosen, databasePath: f.chosenPath)))
    #expect(custom.databasePath == f.chosenPath)
    #expect(custom.highWaterURL == f.customMark)  // in the app's storage, not beside the vault
    #expect(custom.isUsable && custom.isCustom)

    let gone = f.model(.unavailable(path: f.chosenPath, reason: "unplugged"))
    #expect(gone.databasePath == f.chosenPath)
    #expect(gone.highWaterURL == f.customMark)
    #expect(!gone.isUsable && gone.isCustom)
    #expect(gone.unavailableReason == "unplugged")
  }

  // MARK: - Moving into a chosen folder

  @Test func movingCopiesVerifiesSwitchesAndRetires() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    try await makeVault(at: f.defaultPath, accounts: 2)
    let model = f.model()

    await model.move(to: f.chosen, f.recorder.hooks)

    guard case .movedNeedsRelaunch(let moved) = model.step else {
      Issue.record("expected .movedNeedsRelaunch, got \(model.step)")
      return
    }
    #expect(model.needsRelaunch)
    #expect(moved.destination.hasSuffix("chosen/PassFort/vault.sqlite"))
    #expect(f.recorder.events == ["begin", "release"])  // no abandon: backups stay paused

    // The pointer switched...
    let record = try #require(f.store.load())
    #expect(record.path == f.chosen.path(percentEncoded: false))
    // ...the new vault opens, with the mark in the app's storage and not beside it...
    #expect(try await count(at: f.chosenPath, mark: f.customMark) == 2)
    #expect(!exists(f.chosenPath + ".hw"))
    // ...and the old one was kept aside, not deleted.
    #expect(!exists(f.defaultPath))
    let kept = try #require(moved.oldKeptAs)
    #expect(exists((f.defaultPath as NSString).deletingLastPathComponent + "/" + kept))
  }

  @Test func aSecondMoveIsIgnoredOnceOneIsPendingRelaunch() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    try await makeVault(at: f.defaultPath, accounts: 1)
    let model = f.model()
    await model.move(to: f.chosen, f.recorder.hooks)
    let events = f.recorder.events

    await model.move(to: f.root, f.recorder.hooks)

    #expect(f.recorder.events == events)
    #expect(model.needsRelaunch)
  }

  // MARK: - Refusals

  @Test func aNetworkDriveIsRefusedBeforeAnythingHappens() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    try await makeVault(at: f.defaultPath, accounts: 1)
    let model = f.model(checker: FakeChecker(problem: .networkVolume))

    await model.move(to: f.chosen, f.recorder.hooks)

    #expect(model.step == .failed(LocationProblem.networkVolume.message))
    #expect(f.recorder.events.isEmpty)  // not even begun: no lock, no pause
    #expect(f.store.load() == nil)
    #expect(try await count(at: f.defaultPath) == 1)
  }

  @Test func aBackupInFlightRefusesTheMove() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    try await makeVault(at: f.defaultPath, accounts: 1)
    f.recorder.refusal = "A backup is running. Try again in a moment."
    let model = f.model()

    await model.move(to: f.chosen, f.recorder.hooks)

    #expect(model.step == .failed("A backup is running. Try again in a moment."))
    #expect(f.recorder.events == ["begin"])
    #expect(f.store.load() == nil)
    #expect(try await count(at: f.defaultPath) == 1)
  }

  @Test func aDifferentVaultAtTheTargetIsRefusedAndTheOldOneStaysActive() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    try await makeVault(at: f.defaultPath, accounts: 1)
    try await makeVault(at: f.chosenPath, mark: f.customMark, accounts: 4)  // someone else's
    let model = f.model()

    await model.move(to: f.chosen, f.recorder.hooks)

    guard case .failed(let message) = model.step else {
      Issue.record("expected .failed, got \(model.step)")
      return
    }
    #expect(message.contains("different PassFort vault"))
    #expect(f.recorder.events == ["begin", "release", "abandon"])  // backups resume
    #expect(f.store.load() == nil)  // the pointer never switched
    #expect(try await count(at: f.defaultPath) == 1)  // still the active vault, untouched
    #expect(try await count(at: f.chosenPath, mark: f.customMark) == 4)
  }

  // MARK: - Back to the default

  @Test func movingBackRestoresTheSidecarMarkAndClearsThePointer() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    try await makeVault(at: f.chosenPath, mark: f.customMark, accounts: 3)
    f.store.save(VaultLocationRecord(bookmark: Data(), path: f.chosen.path(percentEncoded: false)))
    let model = f.model(.custom(.init(folder: f.chosen, databasePath: f.chosenPath)))

    await model.useDefaultLocation(f.recorder.hooks)

    #expect(model.needsRelaunch)
    #expect(f.store.load() == nil)
    #expect(try await count(at: f.defaultPath) == 3)  // opens with the default `<db>.hw` mark
    #expect(!exists(f.chosenPath))
  }

  @Test func theDefaultLocationHasNothingToMoveBackTo() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    let model = f.model(.standard)

    await model.useDefaultLocation(f.recorder.hooks)

    #expect(model.step == .idle)
    #expect(f.recorder.events.isEmpty)
  }

  // MARK: - An unreachable current location

  @Test func fromAnUnavailableLocationAMoveIsPointerOnly() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    // The vault already exists in the folder being chosen (the drive came back at another path).
    try await makeVault(at: f.chosenPath, mark: f.customMark, accounts: 2)
    let model = f.model(.unavailable(path: "/Volumes/Gone/PassFort/vault.sqlite", reason: "gone"))

    await model.move(to: f.chosen, f.recorder.hooks)

    guard case .movedNeedsRelaunch(let moved) = model.step else {
      Issue.record("expected .movedNeedsRelaunch, got \(model.step)")
      return
    }
    #expect(moved.oldKeptAs == nil)  // nothing was retired: there was nothing to read
    #expect(f.store.load() != nil)
    #expect(try await count(at: f.chosenPath, mark: f.customMark) == 2)  // untouched
  }

  // MARK: - AppModel really uses the mark's location

  @Test func appModelKeepsTheMarkWhereItWasTold() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    let model = AppModel(databasePath: f.chosenPath, highWaterURL: f.customMark)
    #expect(model.state == .needsVault)

    _ = await model.createVault(password: password, recovery: false)

    #expect(model.state == .unlocked)
    #expect(exists(f.customMark.path(percentEncoded: false)))
    #expect(!exists(f.chosenPath + ".hw"))

    model.lock()
    await model.unlock(password: password)
    #expect(model.state == .unlocked)
  }
}
