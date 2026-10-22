import Foundation
import PassFortCrypto
import Testing

@testable import PassFortVault

@Suite struct PasswordChangeTests {

  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }
  private let device = UUID(uuid: (5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5))

  private func tempPath() throws -> (dir: URL, path: String) {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-pw-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (dir, dir.appending(path: "vault.sqlite").path(percentEncoded: false))
  }

  @Test func newPasswordOpensAndOldOneDoesNot() async throws {
    let (dir, path) = try tempPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    let old = Data("old".utf8)
    let new = Data("new".utf8)
    let repo = try await Vault.create(
      databasePath: path, password: old, params: fastParams, deviceID: device)
    let made = try await repo.create(AccountPayload(title: "bank", password: "hunter2"))

    let key = try await repo.changePassword(current: old, new: new, issueRecoveryKey: false)
    #expect(key == nil)

    // The live session keeps working -- same DEK.
    #expect(try await repo.account(id: made.id)?.payload.password == "hunter2")

    await #expect(throws: PassFortError.authFailed) {
      try await Vault.unlock(databasePath: path, password: old, deviceID: device)
    }
    let reopened = try await Vault.unlock(databasePath: path, password: new, deviceID: device)
    #expect(try await reopened.account(id: made.id)?.payload.password == "hunter2")
  }

  @Test func wrongCurrentPasswordLeavesTheHeaderAlone() async throws {
    let (dir, path) = try tempPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    let repo = try await Vault.create(
      databasePath: path, password: Data("right".utf8), params: fastParams, deviceID: device)
    let before = try await repo.header()

    await #expect(throws: PassFortError.authFailed) {
      try await repo.changePassword(
        current: Data("wrong".utf8), new: Data("new".utf8), issueRecoveryKey: true)
    }
    #expect(try await repo.header() == before)
    _ = try await Vault.unlock(
      databasePath: path, password: Data("right".utf8), deviceID: device)
  }

  @Test func theOldRecoveryKeyStopsWorkingAndANewOneIsIssued() async throws {
    let (dir, path) = try tempPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    let old = Data("old".utf8)
    let (repo, oldKey) = try await Vault.createWithRecovery(
      databasePath: path, password: old, params: fastParams, deviceID: device)

    let newKey = try #require(
      try await repo.changePassword(current: old, new: Data("new".utf8), issueRecoveryKey: true))
    #expect(newKey != oldKey)

    await #expect(throws: PassFortError.authFailed) {
      try await Vault.recover(
        databasePath: path, recoveryKey: oldKey, newPassword: Data("x".utf8), deviceID: device)
    }
    _ = try await Vault.recover(
      databasePath: path, recoveryKey: newKey, newPassword: Data("y".utf8), deviceID: device)
  }

  @Test func withoutARecoveryKeyTheVaultBecomesPasswordOnly() async throws {
    let (dir, path) = try tempPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    let old = Data("old".utf8)
    let (repo, oldKey) = try await Vault.createWithRecovery(
      databasePath: path, password: old, params: fastParams, deviceID: device)

    _ = try await repo.changePassword(current: old, new: Data("new".utf8), issueRecoveryKey: false)

    await #expect(throws: PassFortError.notFound) {
      try await Vault.recover(
        databasePath: path, recoveryKey: oldKey, newPassword: Data("x".utf8), deviceID: device)
    }
  }

  @Test func vaultVersionDoesNotMove() async throws {
    let (dir, path) = try tempPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    let old = Data("old".utf8)
    let repo = try await Vault.create(
      databasePath: path, password: old, params: fastParams, deviceID: device)
    _ = try await repo.create(AccountPayload(title: "a"))
    let database = try VaultDatabase(path: path)
    let before = try await database.dbQueue.read { try VaultMeta.readVaultVersion($0) }

    _ = try await repo.changePassword(current: old, new: Data("new".utf8), issueRecoveryKey: true)

    let after = try await database.dbQueue.read { try VaultMeta.readVaultVersion($0) }
    #expect(after == before)
  }
}
