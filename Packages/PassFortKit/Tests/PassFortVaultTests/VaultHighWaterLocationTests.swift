import Foundation
import PassFortCrypto
import Testing

@testable import PassFortVault

/// The anti-rollback mark can live somewhere other than `<db>.hw` (the app does this for a vault
/// in a user-chosen folder), and every `Vault` entry point honours that.
@Suite struct VaultHighWaterLocationTests {

  private let params = KdfParameters(
    kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  private let device = UUID(uuid: (7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7))
  private let password = Data("correct horse".utf8)

  private struct Scratch {
    let dir: URL
    var vaultPath: String { dir.appending(path: "vault.sqlite").path(percentEncoded: false) }
    var markURL: URL { dir.appending(path: "elsewhere.hw") }
    func remove() { try? FileManager.default.removeItem(at: dir) }
  }

  private func makeScratch() throws -> Scratch {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-hw-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return Scratch(dir: dir)
  }

  private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

  @Test func createWritesTheMarkWhereItIsTold() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let mark = HighWaterMark(url: s.markURL)

    let repo = try await Vault.create(
      databasePath: s.vaultPath, password: password, params: params, deviceID: device,
      highWater: mark)
    _ = try await repo.create(AccountPayload(title: "a", username: "u", password: "p"))

    #expect(exists(s.markURL.path(percentEncoded: false)))
    #expect(try mark.read() > 0)
    #expect(!exists(s.vaultPath + ".hw"))  // not beside the vault
  }

  @Test func theDefaultIsStillTheSidecarBesideTheVault() async throws {
    let s = try makeScratch()
    defer { s.remove() }

    _ = try await Vault.create(
      databasePath: s.vaultPath, password: password, params: params, deviceID: device)

    #expect(exists(s.vaultPath + ".hw"))
  }

  @Test func unlockChecksRollbackAgainstTheGivenMark() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let mark = HighWaterMark(url: s.markURL)
    do {
      _ = try await Vault.create(
        databasePath: s.vaultPath, password: password, params: params, deviceID: device,
        highWater: mark)
    }
    try mark.write(9)  // this Mac last saw version 9; the file is at 0

    await #expect(throws: VaultManifest.Failure.self) {
      _ = try await Vault.unlock(
        databasePath: s.vaultPath, password: password, deviceID: device, highWater: mark)
    }
    // A sidecar beside the vault would not have caught it: there is none, so it reads as 0.
    _ = try await Vault.unlock(
      databasePath: s.vaultPath, password: password, deviceID: device)
  }

  @Test func resetClearsTheGivenMarkAndTheNextUnlockRepairsIt() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let mark = HighWaterMark(url: s.markURL)
    do {
      _ = try await Vault.create(
        databasePath: s.vaultPath, password: password, params: params, deviceID: device,
        highWater: mark)
    }
    try mark.write(9)
    try mark.reset()

    _ = try await Vault.unlock(
      databasePath: s.vaultPath, password: password, deviceID: device, highWater: mark)

    #expect(try mark.read() == 0)  // repaired forward to the file's version
  }

  @Test func createWithRecoveryAndRecoverHonourItToo() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let mark = HighWaterMark(url: s.markURL)

    let (repo, key) = try await Vault.createWithRecovery(
      databasePath: s.vaultPath, password: password, params: params, deviceID: device,
      highWater: mark)
    _ = try await repo.create(AccountPayload(title: "a", username: "u", password: "p"))
    #expect(exists(s.markURL.path(percentEncoded: false)))
    #expect(!exists(s.vaultPath + ".hw"))

    _ = try await Vault.recover(
      databasePath: s.vaultPath, recoveryKey: key, newPassword: Data("new pw".utf8),
      deviceID: device, highWater: mark)
    #expect(!exists(s.vaultPath + ".hw"))
  }
}
