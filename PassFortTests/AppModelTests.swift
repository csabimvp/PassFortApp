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

  @Test func changePasswordWithANewRecoveryKeyShowsItThenUnlocks() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "v.sqlite").path(percentEncoded: false)
    try await makeVault(at: path, password: "old")

    let model = AppModel(databasePath: path)
    await model.unlock(password: Data("old".utf8))
    let error = await model.changePassword(
      current: Data("old".utf8), new: Data("new".utf8), issueRecoveryKey: true)
    #expect(error == nil)
    guard case .showingRecoveryKey = model.state else {
      Issue.record("expected .showingRecoveryKey, got \(model.state)")
      return
    }
    await model.confirmRecoveryKeyShown()
    #expect(model.state == .unlocked)

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
    let error = await model.changePassword(
      current: Data("nope".utf8), new: Data("new".utf8), issueRecoveryKey: false)
    #expect(error == .wrongPassword)
    #expect(model.state == .unlocked)
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
