import Foundation
import PassFortCrypto
import Testing

@testable import PassFortVault

@Suite struct VaultRecoveryTests {

  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }
  private let device = UUID(uuid: (4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4))

  private func tempPath() throws -> (dir: URL, path: String) {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-rec-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (dir, dir.appending(path: "vault.sqlite").path(percentEncoded: false))
  }

  @Test func recoverOpensTheVaultAndRotatesThePassword() async throws {
    let (dir, path) = try tempPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    let oldPassword = Data("forgotten".utf8)
    let (repo, recovery) = try await Vault.createWithRecovery(
      databasePath: path, password: oldPassword, params: fastParams, deviceID: device)
    let made = try await repo.create(AccountPayload(title: "bank", password: "hunter2"))

    // Recover with the grouped key string a user would have written down.
    let newPassword = Data("remembered".utf8)
    let recovered = try await Vault.recover(
      databasePath: path, recoveryKey: try RecoveryKey(grouped: recovery.grouped),
      newPassword: newPassword, deviceID: device)

    let fetched = try await recovered.account(id: made.id)
    #expect(fetched?.payload.password == "hunter2")  // same DEK -> records intact

    // The old password no longer opens; the new one does.
    await #expect(throws: PassFortError.authFailed) {
      try await Vault.unlock(databasePath: path, password: oldPassword, deviceID: device)
    }
    _ = try await Vault.unlock(databasePath: path, password: newPassword, deviceID: device)
  }

  @Test func recoverRejectsAWrongKey() async throws {
    let (dir, path) = try tempPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    _ = try await Vault.createWithRecovery(
      databasePath: path, password: Data("pw".utf8), params: fastParams, deviceID: device)

    let wrong = try RecoveryKey(raw: Data(repeating: 0xEE, count: 32))
    await #expect(throws: PassFortError.authFailed) {
      try await Vault.recover(
        databasePath: path, recoveryKey: wrong, newPassword: Data("new".utf8), deviceID: device)
    }
  }

  @Test func rotateRecoveryKeyInvalidatesTheOldOne() async throws {
    let (dir, path) = try tempPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    let (repo, first) = try await Vault.createWithRecovery(
      databasePath: path, password: Data("pw".utf8), params: fastParams, deviceID: device)

    let second = try await repo.rotateRecoveryKey()
    #expect(second != first)

    // The old key no longer opens slot 1; the new one does.
    await #expect(throws: PassFortError.authFailed) {
      try await Vault.recover(
        databasePath: path, recoveryKey: first, newPassword: Data("x".utf8), deviceID: device)
    }
    _ = try await Vault.recover(
      databasePath: path, recoveryKey: second, newPassword: Data("y".utf8), deviceID: device)
  }

  @Test func vaultExistsReflectsWhetherAVaultIsThere() async throws {
    let (dir, path) = try tempPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    #expect(!Vault.exists(databasePath: path))
    _ = try await Vault.create(
      databasePath: path, password: Data("pw".utf8), params: fastParams, deviceID: device)
    #expect(Vault.exists(databasePath: path))
  }

  @Test func createWithoutRecoveryHasNoSlotToRecoverFrom() async throws {
    let (dir, path) = try tempPath()
    defer { try? FileManager.default.removeItem(at: dir) }

    _ = try await Vault.create(
      databasePath: path, password: Data("pw".utf8), params: fastParams, deviceID: device)

    await #expect(throws: PassFortError.notFound) {
      try await Vault.recover(
        databasePath: path, recoveryKey: RecoveryKey.generate(),
        newPassword: Data("x".utf8), deviceID: device)
    }
  }
}
