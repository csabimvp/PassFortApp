import Foundation
import PassFortCrypto
import PassFortVault
import SQLite3
import Testing

@testable import PassFort

/// The §13.1 "UI state machine (locked / unlocking / unlocked / error)" tests —
/// they drive `AppModel` directly, no UI.
@MainActor
struct AppModelTests {

  // A cheap KDF — same shape the PassFortVaultTests suites use.
  private let fastParams = KdfParameters(
    kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))

  private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "pf-app-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func makeVault(at path: String, password: String = "correct horse") async throws {
    _ = try await Vault.create(
      databasePath: path, password: Data(password.utf8), params: fastParams,
      deviceID: VaultService.deviceID)
  }

  // MARK: - First run / unlock

  @Test func freshPathNeedsAVault() {
    let model = AppModel(databasePath: "/tmp/pf-does-not-exist-\(UUID().uuidString).sqlite")
    #expect(model.state == .needsVault)
  }

  @Test func existingVaultStartsLocked() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path)

    #expect(AppModel(databasePath: path).state == .locked())
  }

  @Test func wrongPasswordStaysLockedWithNoRepo() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "right")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("wrong".utf8))

    #expect(model.state == .locked(.wrongPassword))
    #expect(model.repo == nil)
  }

  @Test func rightPasswordUnlocks() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "sesame")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("sesame".utf8))

    #expect(model.state == .unlocked)
    #expect(model.repo != nil)
    #expect(model.summaries.isEmpty)
  }

  @Test func unlockThenLockTearsDown() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "pw")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    _ = await model.createAccount(AccountPayload(title: "GitHub"))
    #expect(model.summaries.count == 1)

    model.lock()
    #expect(model.state == .locked())
    #expect(model.repo == nil)
    #expect(model.summaries.isEmpty)
  }

  // MARK: - Create flow

  @Test func createWithoutRecoveryGoesStraightToUnlocked() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)

    let model = AppModel(databasePath: path)
    #expect(model.state == .needsVault)
    let error = await model.createVault(password: Data("new".utf8), recovery: false)

    #expect(error == nil)
    #expect(model.state == .unlocked)
    #expect(model.repo != nil)
  }

  @Test func createWithRecoveryShowsTheKeyThenUnlocks() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)

    let model = AppModel(databasePath: path)
    _ = await model.createVault(password: Data("new".utf8), recovery: true)

    guard case .showingRecoveryKey = model.state else {
      Issue.record("expected .showingRecoveryKey, got \(model.state)")
      return
    }
    #expect(model.repo == nil)  // still parked in stagedRepo

    await model.confirmRecoveryKeyShown()
    #expect(model.state == .unlocked)
    #expect(model.repo != nil)
  }

  @Test func lockingWhileTheRecoveryKeyIsShownReleasesTheStagedVault() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)

    let model = AppModel(databasePath: path)
    _ = await model.createVault(password: Data("new".utf8), recovery: true)
    #expect(model.stagedRepo != nil)

    model.lock()  // the auto-lock firing while the key is on screen
    #expect(model.state == .locked())
    #expect(model.stagedRepo == nil)
    #expect(model.repo == nil)
  }

  // MARK: - Password change

  /// The key comes back to the caller (the Settings sheet shows it); the main window stays on the
  /// vault rather than switching to `.showingRecoveryKey` behind the Settings window.
  @Test func changePasswordWithANewRecoveryKeyReturnsItAndStaysUnlocked() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "old")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("old".utf8))
    let result = await model.changePassword(
      current: Data("old".utf8), new: Data("new".utf8), issueRecoveryKey: true)
    let key = try #require(try result.get())
    #expect(model.state == .unlocked)
    #expect(model.stagedRepo == nil)

    let repo = try #require(model.repo)
    _ = try VaultSession.openWithRecovery(header: try await repo.header(), recoveryKey: key.raw)

    model.lock()
    await model.unlock(password: Data("old".utf8))
    #expect(model.state == .locked(.wrongPassword))
    await model.unlock(password: Data("new".utf8))
    #expect(model.state == .unlocked)
  }

  @Test func changePasswordWithAWrongCurrentPasswordStaysUnlocked() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "old")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("old".utf8))
    let result = await model.changePassword(
      current: Data("nope".utf8), new: Data("new".utf8), issueRecoveryKey: false)
    #expect(result == .failure(.wrongPassword))
    #expect(model.state == .unlocked)
  }

  // MARK: - Recovery-key rotation

  /// Rotation used to drop a failure (`try?`) and switch the main window to the key; now the key
  /// comes back to the Settings sheet, the vault stays open, and the old key stops working.
  @Test func rotateRecoveryKeyReturnsTheKeyAndStaysUnlocked() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "old")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("old".utf8))
    let first = try await model.rotateRecoveryKey().get()
    let second = try await model.rotateRecoveryKey().get()
    #expect(model.state == .unlocked)
    #expect(model.stagedRepo == nil)

    let header = try await #require(model.repo).header()
    _ = try VaultSession.openWithRecovery(header: header, recoveryKey: second.raw)
    #expect(throws: PassFortError.authFailed) {
      _ = try VaultSession.openWithRecovery(header: header, recoveryKey: first.raw)
    }
  }

  @Test func rotateRecoveryKeyWhileLockedFails() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "old")

    let model = AppModel(databasePath: path)
    guard case .failure = await model.rotateRecoveryKey() else {
      Issue.record("expected a failure while locked")
      return
    }
    #expect(model.state == .locked())
  }

  // MARK: - Start a new vault

  /// The files set aside beside the vault (`.pre-new-`, `.pre-load-`), by name.
  private func setAsideFiles(in dir: URL, label: String = "pre-new") throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
      .filter { $0.contains(".\(label)-") }
  }

  @Test func startNewVaultReplacesTheVaultAndKeepsTheOldOne() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "old")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("old".utf8))
    _ = await model.createAccount(AccountPayload(title: "GitHub"))
    var calls: [String] = []
    let hooks = AppModel.ReplaceVaultHooks(
      begin: {
        calls.append("begin")
        return nil
      },
      end: { calls.append("end") })

    let result = await model.startNewVault(
      current: Data("old".utf8), password: Data("fresh".utf8), recovery: false, hooks)

    let keptAt = try result.get()
    #expect(calls == ["begin", "end"])
    #expect(model.state == .unlocked)
    #expect(model.summaries.isEmpty)
    let oldID = try #require(VaultBackup.inspect(URL(fileURLWithPath: keptAt))).vaultID
    let newID = try #require(VaultBackup.inspect(URL(fileURLWithPath: path))).vaultID
    #expect(oldID != newID)

    // The new vault opens with its own password -- the old mark was reset, so no false rollback.
    model.lock()
    await model.unlock(password: Data("old".utf8))
    #expect(model.state == .locked(.wrongPassword))
    await model.unlock(password: Data("fresh".utf8))
    #expect(model.state == .unlocked)

    // The old vault is whole: its WAL went with it (or was checkpointed into it on close).
    let old = try await Vault.unlock(
      databasePath: keptAt, password: Data("old".utf8), deviceID: VaultService.deviceID,
      highWater: HighWaterMark(url: dir.appending(path: "old.hw")))
    #expect(try await old.summaries().map(\.title) == ["GitHub"])
  }

  @Test func startNewVaultWithARecoveryKeyShowsItThenUnlocks() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "old")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("old".utf8))
    let result = await model.startNewVault(
      current: Data("old".utf8), password: Data("fresh".utf8), recovery: true)

    #expect((try? result.get()) != nil)
    guard case .showingRecoveryKey = model.state else {
      Issue.record("expected .showingRecoveryKey, got \(model.state)")
      return
    }
    #expect(model.repo == nil)
    await model.confirmRecoveryKeyShown()
    #expect(model.state == .unlocked)
    #expect(model.summaries.isEmpty)
  }

  @Test func startNewVaultWithAWrongCurrentPasswordChangesNothing() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "old")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("old".utf8))
    _ = await model.createAccount(AccountPayload(title: "GitHub"))
    var began = false
    let result = await model.startNewVault(
      current: Data("nope".utf8), password: Data("fresh".utf8), recovery: false,
      AppModel.ReplaceVaultHooks(
        begin: {
          began = true
          return nil
        }, end: {}))

    #expect(result == .failure(.wrongPassword))
    #expect(!began)
    #expect(model.state == .unlocked)
    #expect(model.summaries.count == 1)
    #expect(try setAsideFiles(in: dir).isEmpty)
  }

  @Test func aRefusedStartChangesNothing() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "old")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("old".utf8))
    var ended = false
    let result = await model.startNewVault(
      current: Data("old".utf8), password: Data("fresh".utf8), recovery: false,
      AppModel.ReplaceVaultHooks(begin: { "A backup is running." }, end: { ended = true }))

    #expect(result == .failure(.notNow("A backup is running.")))
    #expect(!ended)
    #expect(model.state == .unlocked)
    #expect(try setAsideFiles(in: dir).isEmpty)
  }

  @Test func startNewVaultNeedsAnUnlockedVault() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "old")

    let model = AppModel(databasePath: path)
    let result = await model.startNewVault(
      current: Data("old".utf8), password: Data("fresh".utf8), recovery: false)

    #expect((try? result.get()) == nil)
    #expect(model.state == .locked())
    #expect(try setAsideFiles(in: dir).isEmpty)
  }

  /// The failure path of `startNewVault`: whatever a failed create left behind is removed, and the
  /// old vault comes back with the mark it had.
  @Test func puttingBackRestoresTheOldVaultAndItsMark() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    do {  // closed before its files move, as `startNewVault` does
      let repo = try await Vault.create(
        databasePath: path, password: Data("old".utf8), params: fastParams,
        deviceID: VaultService.deviceID)
      _ = try await repo.create(AccountPayload(title: "GitHub"))
    }
    let service = VaultService(databasePath: path)
    let mark = HighWaterMark(sidecarFor: path)
    let before = try mark.read()
    #expect(before > 0)

    let aside = try service.setAside(label: "pre-new")
    #expect(!FileManager.default.fileExists(atPath: path))
    #expect(aside.mark == before)
    // A create that got as far as a database file and a reset mark, then failed.
    try Data("half-made".utf8).write(to: URL(fileURLWithPath: path))
    try mark.write(0)

    service.putBack(aside)

    #expect(try mark.read() == before)
    #expect(try setAsideFiles(in: dir).isEmpty)
    let reopened = try await service.unlock(password: Data("old".utf8))
    #expect(try await reopened.summaries().map(\.title) == ["GitHub"])
  }

  // MARK: - Load a vault

  /// A closed vault at `path` holding one account per title. Returns its vault id.
  @discardableResult
  private func makeVault(at path: String, password: String, titles: [String]) async throws -> UUID {
    do {
      let repo = try await Vault.create(
        databasePath: path, password: Data(password.utf8), params: fastParams,
        deviceID: VaultService.deviceID,
        highWater: HighWaterMark(url: URL(fileURLWithPath: path + ".scratch.hw")))
      for title in titles { _ = try await repo.create(AccountPayload(title: title)) }
    }
    return try #require(VaultBackup.inspect(URL(fileURLWithPath: path))).vaultID
  }

  @Test func loadingAnotherVaultMakesItLiveAndKeepsTheOld() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    let other = dir.appending(path: "elsewhere/other.sqlite")
    try FileManager.default.createDirectory(
      at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
    try await makeVault(at: path, password: "a-pw")
    let otherID = try await makeVault(
      at: other.path(percentEncoded: false), password: "b-pw", titles: ["Bank"])

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("a-pw".utf8))
    // More writes than the other vault has, so this Mac's mark is ahead of the loaded file.
    for title in ["One", "Two", "Three", "Four"] {
      _ = await model.createAccount(AccountPayload(title: title))
    }
    var calls: [String] = []
    let hooks = AppModel.ReplaceVaultHooks(
      begin: {
        calls.append("begin")
        return nil
      },
      end: { calls.append("end") })

    let keptAt = try await model.loadVault(from: other, password: Data("b-pw".utf8), hooks).get()

    #expect(calls == ["begin", "end"])
    #expect(model.state == .unlocked)
    #expect(model.summaries.map(\.title) == ["Bank"])
    #expect(VaultBackup.inspect(URL(fileURLWithPath: path))?.vaultID == otherID)
    #expect(VaultBackup.inspect(other)?.vaultID == otherID)  // copied, not moved
    #expect(keptAt.hasPrefix(path + ".pre-load-"))
    #expect(FileManager.default.fileExists(atPath: keptAt))

    // No false rollback: the mark now belongs to the loaded vault.
    model.lock()
    await model.unlock(password: Data("b-pw".utf8))
    #expect(model.state == .unlocked)

    // The previous vault is whole where it was kept.
    let previous = try await Vault.unlock(
      databasePath: keptAt, password: Data("a-pw".utf8), deviceID: VaultService.deviceID,
      highWater: HighWaterMark(url: dir.appending(path: "previous.hw")))
    #expect(try await previous.summaries().count == 4)
  }

  /// A vault still open elsewhere (the CLI, say) has its latest writes only in its `-wal`; they
  /// are loaded too.
  @Test func loadingCarriesWritesStillInTheLog() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    let other = dir.appending(path: "other.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "a-pw")
    let open = try await Vault.create(
      databasePath: other, password: Data("b-pw".utf8), params: fastParams,
      deviceID: VaultService.deviceID, highWater: HighWaterMark(url: dir.appending(path: "o.hw")))
    _ = try await open.create(AccountPayload(title: "Only in the log"))
    let walSize = try FileManager.default.attributesOfItem(atPath: other + "-wal")[.size] as? Int
    #expect((walSize ?? 0) > 0)

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("a-pw".utf8))
    let result = await model.loadVault(
      from: URL(fileURLWithPath: other), password: Data("b-pw".utf8))

    #expect((try? result.get()) != nil)
    #expect(model.summaries.map(\.title) == ["Only in the log"])
    _ = open
  }

  @Test func loadingWithAWrongPasswordChangesNothing() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    let other = dir.appending(path: "other.sqlite")
    try await makeVault(at: path, password: "a-pw")
    try await makeVault(at: other.path(percentEncoded: false), password: "b-pw", titles: ["Bank"])

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("a-pw".utf8))
    _ = await model.createAccount(AccountPayload(title: "GitHub"))
    var began = false
    let result = await model.loadVault(
      from: other, password: Data("nope".utf8),
      AppModel.ReplaceVaultHooks(
        begin: {
          began = true
          return nil
        }, end: {}))

    #expect(result == .failure(.wrongPassword))
    #expect(!began)
    #expect(model.state == .unlocked)
    #expect(model.summaries.map(\.title) == ["GitHub"])
    #expect(try setAsideFiles(in: dir, label: "pre-load").isEmpty)
  }

  @Test func loadingACopyOfTheOpenVaultIsRefused() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "a-pw")
    let copy = dir.appending(path: "copy.sqlite")
    try VaultBackup.create(databasePath: path, to: copy)

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("a-pw".utf8))
    let result = await model.loadVault(from: copy, password: Data("a-pw".utf8))

    guard case .failure(.loadRefused(let message)) = result else {
      Issue.record("expected .loadRefused, got \(result)")
      return
    }
    #expect(message.contains("Restore from Backup"))
    #expect(model.state == .unlocked)
    #expect(try setAsideFiles(in: dir, label: "pre-load").isEmpty)
  }

  @Test func loadingAFileThatIsNotAVaultIsRefused() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "a-pw")
    let junk = dir.appending(path: "notes.txt")
    try Data("not a vault".utf8).write(to: junk)

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("a-pw".utf8))
    let result = await model.loadVault(from: junk, password: Data("a-pw".utf8))

    #expect(result == .failure(.loadRefused("That file isn't a PassFort vault.")))
    #expect(model.state == .unlocked)
  }

  @Test func loadingNeedsAnUnlockedVault() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    let other = dir.appending(path: "other.sqlite")
    try await makeVault(at: path, password: "a-pw")
    try await makeVault(at: other.path(percentEncoded: false), password: "b-pw", titles: [])

    let model = AppModel(databasePath: path)
    let result = await model.loadVault(from: other, password: Data("b-pw".utf8))

    #expect((try? result.get()) == nil)
    #expect(model.state == .locked())
    #expect(try setAsideFiles(in: dir, label: "pre-load").isEmpty)
  }

  // MARK: - Account writes

  @Test func accountWritesRefreshTheIndexAndBumpTheCounter() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "pw")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    let before = model.writeCounter

    #expect(await model.createAccount(AccountPayload(title: "Bank")) == nil)
    #expect(model.summaries.map(\.title) == ["Bank"])
    #expect(model.writeCounter == before + 1)

    let id = try #require(model.summaries.first).id
    #expect(await model.deleteAccount(id: id) == nil)
    #expect(model.summaries.filter { !$0.isDeleted }.isEmpty)
    #expect(model.writeCounter == before + 2)
  }

  // MARK: - Account reads

  @Test func aRecordTamperedAfterUnlockLoadsAsFailedNotForever() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "pw")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    _ = await model.createAccount(AccountPayload(title: "Bank", password: "hunter2"))
    let id = try #require(model.summaries.first).id
    guard case .loaded = await model.loadAccount(id: id) else {
      Issue.record("an untouched record should load")
      return
    }

    // Behind the app's back: flip a bit in the sealed blob's last byte (inside the AEAD tag).
    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    flipLastSealedByte(db: db)

    guard case .failed = await model.loadAccount(id: id) else {
      Issue.record("a tampered record must load as .failed")
      return
    }
    #expect(model.state == .unlocked)  // reported, not a lock-out
  }

  @Test func anUnknownIDLoadsAsMissing() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "pw")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    guard case .missing = await model.loadAccount(id: UUID()) else {
      Issue.record("expected .missing")
      return
    }
  }

  /// Read every row's `sealed`, flip its last bit, write it back -- raw SQLite, no GRDB, so the
  /// write goes around `VaultRepository` and the manifest exactly as an outside edit would.
  private func flipLastSealedByte(db: OpaquePointer?) {
    var select: OpaquePointer?
    #expect(
      sqlite3_prepare_v2(db, "SELECT rowid, sealed FROM records", -1, &select, nil) == SQLITE_OK)
    defer { sqlite3_finalize(select) }
    var rows: [(Int64, Data)] = []
    while sqlite3_step(select) == SQLITE_ROW {
      let rowid = sqlite3_column_int64(select, 0)
      let count = Int(sqlite3_column_bytes(select, 1))
      guard let bytes = sqlite3_column_blob(select, 1) else { continue }
      var data = Data(bytes: bytes, count: count)
      data[data.count - 1] ^= 0x01
      rows.append((rowid, data))
    }
    #expect(!rows.isEmpty)
    for (rowid, data) in rows {
      var update: OpaquePointer?
      #expect(
        sqlite3_prepare_v2(db, "UPDATE records SET sealed = ? WHERE rowid = ?", -1, &update, nil)
          == SQLITE_OK)
      defer { sqlite3_finalize(update) }
      // SQLITE_TRANSIENT: SQLite copies the bytes, so the buffer may go out of scope.
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      data.withUnsafeBytes { buffer in
        _ = sqlite3_bind_blob(update, 1, buffer.baseAddress, Int32(buffer.count), transient)
      }
      sqlite3_bind_int64(update, 2, rowid)
      #expect(sqlite3_step(update) == SQLITE_DONE)
    }
  }

  // MARK: - Recently Deleted

  @Test func aDeletedAccountCanBeRestoredOrErased() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "pw")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    _ = await model.createAccount(AccountPayload(title: "Keep"))
    _ = await model.createAccount(AccountPayload(title: "Erase"))
    for summary in model.summaries { _ = await model.deleteAccount(id: summary.id) }
    #expect(Set(model.deletedSummaries.map(\.title)) == ["Keep", "Erase"])

    let keep = try #require(model.deletedSummaries.first { $0.title == "Keep" })
    #expect(await model.restoreAccount(id: keep.id) == nil)
    #expect(model.deletedSummaries.map(\.title) == ["Erase"])

    #expect(await model.emptyRecentlyDeleted() == nil)
    #expect(model.deletedSummaries.isEmpty)
    #expect(model.summaries.map(\.title) == ["Keep"])
  }

  // MARK: - Password health

  @Test func theAuditReportsReuseWithoutPasswordValues() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "pw")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    _ = await model.createAccount(AccountPayload(title: "A", password: "Vx9#kQ2!mZ7@pL4$"))
    _ = await model.createAccount(AccountPayload(title: "B", password: "Vx9#kQ2!mZ7@pL4$"))

    guard case .success(let findings) = await model.audit() else {
      Issue.record("the audit should run while unlocked")
      return
    }
    #expect(findings.count == 2)
    #expect(findings.allSatisfy { $0.kind == .reused(count: 2) })
    #expect(findings.allSatisfy { HealthGroup($0.kind) == .reused })

    model.lock()
    guard case .failure = await model.audit() else {
      Issue.record("the audit must not run while locked")
      return
    }
  }

  // MARK: - Import

  @Test func importWritesEveryAccountAndLockClosesTheSheet() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "pw")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    let export = "Group/Title\tUsername\tPassword\nBank\tme\tpw1\nMail\tme\tpw2\n"
    let plan = try PasswordSafeImport.plan(Data(export.utf8))
    #expect(await model.importAccounts(plan.accounts.map(\.payload)) == nil)
    #expect(Set(model.summaries.map(\.title)) == ["Bank", "Mail"])
    #expect(plan.duplicates(of: model.summaries).count == 2)  // a second run would skip both

    model.showingImport = true
    model.lock()
    #expect(model.showingImport == false)
  }

  /// File ▸ New Account… opens the form through the model now, so a lock must close it: a
  /// half-typed account must not reappear after the next unlock.
  @Test func lockClosesTheNewAccountForm() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "pw")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    model.showingNewAccount = true
    model.lock()
    #expect(model.showingNewAccount == false)
  }

  @Test func vaultImportPlansFromAnotherVaultAndLockClosesTheSheet() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    let devURL = dir.appending(path: "dev.sqlite")
    try await makeVault(at: path, password: "pw")
    let dev = try await Vault.create(
      databasePath: devURL.path(percentEncoded: false), password: Data("dev".utf8),
      params: fastParams, deviceID: VaultService.deviceID)
    _ = try await dev.create(AccountPayload(title: "Bank", username: "me", password: "p"))

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    let plan = try await model.planVaultImport(
      from: devURL, unlockingWith: .password(Data("dev".utf8))
    ).get()
    #expect(plan.accounts.map(\.payload.title) == ["Bank"])
    #expect(await model.importAccounts(plan.accounts.map(\.payload)) == nil)
    #expect(model.summaries.map(\.title) == ["Bank"])

    model.showingVaultImport = true
    model.lock()
    #expect(model.showingVaultImport == false)
  }

  @Test func vaultImportReportsAWrongPasswordAndRefusesItself() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "v.sqlite")
    try await makeVault(at: url.path(percentEncoded: false), password: "pw")

    let model = AppModel(databasePath: url.path(percentEncoded: false))
    await model.unlock(password: Data("pw".utf8))
    let wrong = await model.planVaultImport(from: url, unlockingWith: .password(Data("no".utf8)))
    #expect(throws: AppError.wrongPassword) { try wrong.get() }
    let itself = await model.planVaultImport(from: url, unlockingWith: .password(Data("pw".utf8)))
    let refusal = AppError.importRefused(
      "That's this vault, or a copy of it. There's nothing to import.")
    #expect(throws: refusal) { try itself.get() }
  }

  // MARK: - Rollback

  @Test func reloadAfterRestoreShowsTheScreenThatMatchesTheDisk() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    let model = AppModel(databasePath: path)
    #expect(model.state == .needsVault)

    try await makeVault(at: path)  // a restore put a vault in place
    model.reloadAfterRestore()
    #expect(model.state == .locked())

    await model.unlock(password: Data("correct horse".utf8))
    #expect(model.state == .unlocked)
    model.reloadAfterRestore()  // an unlocked vault is released, not left open over new files
    #expect(model.repo == nil)
    #expect(model.state == .locked())

    for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
    model.reloadAfterRestore()
    #expect(model.state == .needsVault)
  }

  @Test func aRolledBackVaultOffersRestoreThenUnlocks() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "pw")

    // The file is at vault_version 0; force the anti-rollback mark ahead of it —
    // exactly what a restored-from-backup file looks like. (The file-level
    // detection itself is covered by VaultRepositoryTests.)
    try HighWaterMark(sidecarFor: path).write(5)

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("pw".utf8))
    #expect(model.state == .locked(.rolledBack(fileVersion: 0, lastSeen: 5)))
    #expect(model.repo == nil)

    await model.acceptRestoreAndRetry(password: Data("pw".utf8))
    #expect(model.state == .unlocked)
  }
}
