import Foundation
import PassFortCrypto
import PassFortVault
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

  // MARK: - Rollback

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
