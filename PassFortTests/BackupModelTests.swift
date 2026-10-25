import Foundation
import PassFortCrypto
import PassFortVault
import Testing

@testable import PassFort

/// The rules behind Settings ▸ Backup, driven without UI: a real vault in a temp directory, a
/// fake destination, and a private `UserDefaults` suite.
@MainActor
struct BackupModelTests {

  /// Records what the model hands it; can be told to fail like an unmounted share would.
  private final class FakeDestination: BackupDestination, @unchecked Sendable {
    private let lock = NSLock()
    private var _configured = true
    private var _failure: AppError?
    private var _stored: [String] = []
    private var _pruneKeeps: [Int] = []
    private var _listed: [UUID] = []

    var configured: Bool {
      get { lock.withLock { _configured } }
      set { lock.withLock { _configured = newValue } }
    }
    var failure: AppError? {
      get { lock.withLock { _failure } }
      set { lock.withLock { _failure = newValue } }
    }
    var stored: [String] { lock.withLock { _stored } }
    var pruneKeeps: [Int] { lock.withLock { _pruneKeeps } }
    var listed: [UUID] { lock.withLock { _listed } }

    var isConfigured: Bool { configured }
    var displayName: String { "Fake NAS" }
    var folderURL: URL? { nil }

    @concurrent func store(_ file: URL) async throws -> String {
      if let failure { throw failure }
      guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
        throw AppError.io("the local backup file was missing")
      }
      let name = file.lastPathComponent
      lock.withLock { _stored.append(name) }
      return name
    }

    @concurrent func list(vaultID: UUID) async throws -> [String] {
      if let failure { throw failure }
      lock.withLock { _listed.append(vaultID) }
      return stored
    }

    @concurrent func prune(vaultID: UUID, keep: Int) async throws -> [String] {
      lock.withLock { _pruneKeeps.append(keep) }
      return []
    }
  }

  private struct Fixture {
    let dir: URL
    let path: String
    let destination: FakeDestination
    let defaults: UserDefaults
    let suite: String
    let model: BackupModel
    let repo: VaultRepository

    /// A second model over the same defaults, as after a relaunch.
    @MainActor func relaunched() -> BackupModel {
      BackupModel(
        databasePath: path, destination: destination, bookmarks: NoBookmarks(), defaults: defaults)
    }

    func cleanUp() {
      try? FileManager.default.removeItem(at: dir)
      defaults.removePersistentDomain(forName: suite)
    }
  }

  private struct NoBookmarks: BookmarkStore {
    func load() -> Data? { nil }
    func save(_ bookmark: Data?) {}
  }

  private let fastParams = KdfParameters(
    kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))

  private func makeFixture(configured: Bool = true, accounts: Int = 1) async throws -> Fixture {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-bm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appending(path: "vault.sqlite").path(percentEncoded: false)

    let repo = try await Vault.create(
      databasePath: path, password: Data("correct horse".utf8), params: fastParams,
      deviceID: VaultService.deviceID)
    for i in 0..<accounts {
      _ = try await repo.create(AccountPayload(title: "acct-\(i)", username: "u", password: "p"))
    }

    let suite = "pf-bm-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let destination = FakeDestination()
    destination.configured = configured
    let model = BackupModel(
      databasePath: path, destination: destination, bookmarks: NoBookmarks(), defaults: defaults)
    return Fixture(
      dir: dir, path: path, destination: destination, defaults: defaults, suite: suite,
      model: model, repo: repo)
  }

  // MARK: - Back Up Now

  @Test func backUpNowStoresAFileNamedForTheVaultAndRecordsIt() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }

    await f.model.backUpNow()

    let id = try #require(VaultBackup.inspect(URL(fileURLWithPath: f.path))?.vaultID)
    #expect(f.destination.stored.count == 1)
    #expect(f.destination.stored[0].hasPrefix("passfort-vault-\(id.uuidString.lowercased())-"))
    guard case .succeeded(_, let version) = f.model.status else {
      Issue.record("expected .succeeded, got \(f.model.status)")
      return
    }
    #expect(version > 0)
    #expect(f.destination.pruneKeeps == [BackupModel.defaultKeep])
  }

  @Test func backupCountListsTheLastVaultsBackups() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }

    await f.model.refreshCount()
    #expect(f.model.backupCount == nil, "no backup yet, so no vault to count")

    await f.model.backUpNow()
    let id = try #require(VaultBackup.inspect(URL(fileURLWithPath: f.path))?.vaultID)
    #expect(f.model.backupCount == 1)
    #expect(f.destination.listed.last == id)

    let relaunched = f.relaunched()
    await relaunched.refreshCount()
    #expect(relaunched.backupCount == 1)

    f.destination.failure = .io("the share went away")
    await relaunched.refreshCount()
    #expect(relaunched.backupCount == nil)

    f.model.removeFolder()
    #expect(f.model.backupCount == nil)
  }

  @Test func backUpNowAlwaysWritesEvenWhenNothingChanged() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }

    await f.model.backUpNow()
    try await Task.sleep(for: .milliseconds(1100))  // names are second-granular
    await f.model.backUpNow()

    #expect(f.destination.stored.count == 2)
  }

  @Test func theKeepSettingReachesThePrune() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }
    f.defaults.set(5, forKey: BackupModel.Keys.keep)

    await f.model.backUpNow()

    #expect(f.destination.pruneKeeps == [5])
  }

  @Test func overlappingPressesRunOnlyOneBackup() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }

    async let first: Void = f.model.backUpNow()
    async let second: Void = f.model.backUpNow()
    _ = await (first, second)

    #expect(f.destination.stored.count == 1)
  }

  // MARK: - Automatic, on lock

  @Test func lockingBacksUpOnlyWhenTheVaultChanged() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }

    await f.model.vaultDidLock()
    #expect(f.destination.stored.count == 1)  // first ever: nothing to compare against

    await f.model.vaultDidLock()
    #expect(f.destination.stored.count == 1)  // unchanged: skipped

    try await Task.sleep(for: .milliseconds(1100))
    _ = try await f.repo.create(AccountPayload(title: "new", username: "u", password: "p"))
    await f.model.vaultDidLock()
    #expect(f.destination.stored.count == 2)  // changed: backed up again
  }

  @Test func aSkippedLockLeavesTheStatusAlone() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }
    await f.model.vaultDidLock()
    let before = f.model.status

    await f.model.vaultDidLock()

    #expect(f.model.status == before)
  }

  @Test func theOnLockToggleIsHonoured() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }
    f.defaults.set(false, forKey: BackupModel.Keys.onLock)

    await f.model.vaultDidLock()

    #expect(f.destination.stored.isEmpty)
    #expect(f.model.status == .idle)
  }

  @Test func aPausedModelNeverTouchesTheFilesAMidSwapRestoreIsMoving() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }
    f.model.setPaused(true)

    await f.model.vaultDidLock()
    await f.model.backUpNow()
    #expect(f.destination.stored.isEmpty)
    #expect(f.model.status == .idle)

    f.model.setPaused(false)
    await f.model.backUpNow()
    #expect(f.destination.stored.count == 1)
  }

  @Test func onlyARealLockCountsAsALock() {
    let key = RecoveryKey.generate()
    #expect(BackupModel.isLock(from: .unlocked, to: .locked()))
    #expect(BackupModel.isLock(from: .unlocked, to: .locked(.io("x"))))
    #expect(!BackupModel.isLock(from: .unlocking, to: .locked(.wrongPassword)))  // failed unlock
    #expect(!BackupModel.isLock(from: .locked(), to: .locked()))
    #expect(!BackupModel.isLock(from: .locked(), to: .unlocking))
    #expect(!BackupModel.isLock(from: .unlocked, to: .unlocking))
    #expect(!BackupModel.isLock(from: .showingRecoveryKey(key), to: .unlocked))
    #expect(!BackupModel.isLock(from: .needsVault, to: .locked()))
  }

  @Test func latestOnlyIsTheDefaultAndPrunesToOne() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }
    #expect(f.model.keep == 1)

    await f.model.backUpNow()

    #expect(f.destination.pruneKeeps == [1])
  }

  // MARK: - No folder / failures

  @Test func withoutAFolderManualSaysSoAndAutomaticStaysSilent() async throws {
    let f = try await makeFixture(configured: false)
    defer { f.cleanUp() }

    await f.model.vaultDidLock()
    #expect(f.model.status == .idle)

    await f.model.backUpNow()
    #expect(f.model.failureMessage == AppError.backupNotConfigured.message)
    #expect(f.destination.stored.isEmpty)
  }

  @Test func anUnavailableDestinationFailsVisiblyAndSurvivesRelaunch() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }
    f.destination.failure = .backupDestinationUnavailable("Zeus")

    await f.model.vaultDidLock()  // automatic, nobody watching

    let message = AppError.backupDestinationUnavailable("Zeus").message
    #expect(f.model.failureMessage == message)
    #expect(f.relaunched().failureMessage == message)  // still visible next launch
  }

  @Test func aLaterSuccessClearsTheFailure() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }
    f.destination.failure = .backupDestinationUnavailable("Zeus")
    await f.model.backUpNow()
    #expect(f.model.failureMessage != nil)

    f.destination.failure = nil
    await f.model.backUpNow()

    #expect(f.model.failureMessage == nil)
    #expect(f.relaunched().failureMessage == nil)
    if case .succeeded = f.relaunched().status {} else { Issue.record("status not restored") }
  }

  @Test func aFailedLockBackupIsRetriedNextTimeEvenIfUnchanged() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }
    f.destination.failure = .backupDestinationUnavailable("Zeus")
    await f.model.vaultDidLock()
    #expect(f.destination.stored.isEmpty)

    f.destination.failure = nil
    await f.model.vaultDidLock()

    #expect(f.destination.stored.count == 1)  // a failure must not count as "already backed up"
  }

  @Test func noVaultMeansNothingToBackUp() async throws {
    let f = try await makeFixture()
    defer { f.cleanUp() }
    let empty = BackupModel(
      databasePath: f.dir.appending(path: "missing.sqlite").path(percentEncoded: false),
      destination: f.destination, bookmarks: NoBookmarks(), defaults: f.defaults)

    await empty.backUpNow()

    #expect(empty.failureMessage == AppError.notAVault.message)
    #expect(f.destination.stored.isEmpty)
  }
}
