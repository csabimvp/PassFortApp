import Foundation
import PassFortCrypto
import PassFortVault
import Testing

@testable import PassFort

/// Moving the live vault between locations, with real vaults in temp directories.
struct VaultMoverTests {

  private let params = KdfParameters(
    kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  private let password = Data("correct horse".utf8)

  private struct Scratch {
    let dir: URL
    func path(_ name: String) -> String { dir.appending(path: name).path(percentEncoded: false) }
    func url(_ name: String) -> URL { dir.appending(path: name) }
    func remove() { try? FileManager.default.removeItem(at: dir) }
  }

  private func makeScratch() throws -> Scratch {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-mv-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return Scratch(dir: dir)
  }

  /// A vault with `accounts` accounts at `endpoint`; closed on return.
  private func makeVault(at endpoint: VaultMover.Endpoint, accounts: Int) async throws {
    let repo = try await Vault.create(
      databasePath: endpoint.databasePath, password: password, params: params,
      deviceID: VaultService.deviceID, highWater: endpoint.highWater)
    for i in 0..<accounts {
      _ = try await repo.create(AccountPayload(title: "acct-\(i)", username: "u", password: "p"))
    }
  }

  private func count(at endpoint: VaultMover.Endpoint) async throws -> Int {
    try await Vault.unlock(
      databasePath: endpoint.databasePath, password: password, deviceID: VaultService.deviceID,
      highWater: endpoint.highWater
    ).summaries().filter { !$0.isDeleted }.count
  }

  private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

  // MARK: - copy

  @Test func copiesTheVaultAndItOpensAtTheTargetWithItsOwnMark() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let source = VaultMover.Endpoint(databasePath: s.path("old/vault.sqlite"), highWaterURL: nil)
    let target = VaultMover.Endpoint(
      databasePath: s.path("new/PassFort/vault.sqlite"), highWaterURL: s.url("app/location.hw"))
    try await makeVault(at: source, accounts: 2)

    let copied = try await VaultMover.copy(from: source, to: target)

    #expect(copied.info != nil)
    #expect(copied.replacedAside == nil)
    #expect(try await count(at: target) == 2)  // unlocks: the mark was carried, so no false rollback
    #expect(!exists(target.databasePath + ".hw"))  // and it is not beside the vault
    #expect(try await count(at: source) == 2)  // the old vault is untouched until retire
  }

  @Test func theMarkIsCarriedAndNeverLowered() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let source = VaultMover.Endpoint(databasePath: s.path("old/vault.sqlite"), highWaterURL: nil)
    let markURL = s.url("app/location.hw")
    let target = VaultMover.Endpoint(databasePath: s.path("new/vault.sqlite"), highWaterURL: markURL)
    try await makeVault(at: source, accounts: 3)
    let carried = try source.highWater.read()
    #expect(carried > 0)

    try await VaultMover.copy(from: source, to: target)
    #expect(try HighWaterMark(url: markURL).read() == carried)

    // A mark already further ahead at the target stays.
    try HighWaterMark(url: markURL).write(carried + 40)
    let again = VaultMover.Endpoint(databasePath: s.path("new2/vault.sqlite"), highWaterURL: markURL)
    try await VaultMover.copy(from: source, to: again)
    #expect(try HighWaterMark(url: markURL).read() == carried + 40)
  }

  @Test func aDifferentVaultAtTheTargetIsRefusedAndNothingChanges() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let source = VaultMover.Endpoint(databasePath: s.path("old/vault.sqlite"), highWaterURL: nil)
    let target = VaultMover.Endpoint(databasePath: s.path("new/vault.sqlite"), highWaterURL: nil)
    try await makeVault(at: source, accounts: 1)
    try await makeVault(at: target, accounts: 4)

    await #expect(throws: AppError.self) {
      _ = try await VaultMover.copy(from: source, to: target)
    }

    #expect(try await count(at: target) == 4)  // theirs, untouched
    #expect(try await count(at: source) == 1)
  }

  @Test func anOlderCopyOfTheSameVaultIsReplacedAndKept() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let source = VaultMover.Endpoint(databasePath: s.path("old/vault.sqlite"), highWaterURL: nil)
    let target = VaultMover.Endpoint(databasePath: s.path("new/vault.sqlite"), highWaterURL: nil)
    try await makeVault(at: source, accounts: 1)
    // The target holds an older copy of the same vault.
    try await VaultMover.copy(from: source, to: target)
    let repo = try await Vault.unlock(
      databasePath: source.databasePath, password: password, deviceID: VaultService.deviceID)
    _ = try await repo.create(AccountPayload(title: "newer", username: "u", password: "p"))

    let copied = try await VaultMover.copy(from: source, to: target)

    let kept = try #require(copied.replacedAside)
    #expect(try await count(at: target) == 2)
    #expect(exists(s.path("new/" + kept)))  // the older copy is still there
  }

  @Test func theSameLocationIsRefused() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let endpoint = VaultMover.Endpoint(databasePath: s.path("v/vault.sqlite"), highWaterURL: nil)
    try await makeVault(at: endpoint, accounts: 1)

    await #expect(throws: AppError.locationNotAllowed("The vault is already there.")) {
      _ = try await VaultMover.copy(from: endpoint, to: endpoint)
    }
  }

  @Test func noVaultYetMeansAPointerOnlyChange() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let source = VaultMover.Endpoint(databasePath: s.path("old/vault.sqlite"), highWaterURL: nil)
    let target = VaultMover.Endpoint(databasePath: s.path("new/vault.sqlite"), highWaterURL: nil)

    let copied = try await VaultMover.copy(from: source, to: target)

    #expect(copied == VaultMover.Copied(info: nil, replacedAside: nil))
    #expect(!exists(target.databasePath))
  }

  @Test func anUnreadableSourceIsAlsoPointerOnly() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let target = VaultMover.Endpoint(databasePath: s.path("new/vault.sqlite"), highWaterURL: nil)

    let copied = try await VaultMover.copy(from: nil, to: target)

    #expect(copied.info == nil)
    #expect(!exists(target.databasePath))
  }

  @Test func aSourceThatIsNotAVaultIsRefused() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    try FileManager.default.createDirectory(at: s.url("old"), withIntermediateDirectories: true)
    try Data("junk".utf8).write(to: s.url("old/vault.sqlite"))
    let source = VaultMover.Endpoint(databasePath: s.path("old/vault.sqlite"), highWaterURL: nil)
    let target = VaultMover.Endpoint(databasePath: s.path("new/vault.sqlite"), highWaterURL: nil)

    await #expect(throws: AppError.self) {
      _ = try await VaultMover.copy(from: source, to: target)
    }
    #expect(!exists(target.databasePath))
  }

  // MARK: - retire

  @Test func retiringKeepsEveryOldFileAsideAndNeverDeletes() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let source = VaultMover.Endpoint(databasePath: s.path("old/vault.sqlite"), highWaterURL: nil)
    let repo = try await Vault.create(
      databasePath: source.databasePath, password: password, params: params,
      deviceID: VaultService.deviceID)
    _ = try await repo.create(AccountPayload(title: "a", username: "u", password: "p"))
    #expect(exists(source.databasePath + "-wal"))  // open: the WAL is live

    let kept = try #require(VaultMover.retire(source))

    #expect(!exists(source.databasePath))
    #expect(!exists(source.databasePath + "-wal"))
    #expect(exists(s.path("old/" + kept)))
    #expect(exists(s.path("old/" + kept + "-wal")))
    _ = repo
  }

  @Test func retiringNothingReturnsNil() throws {
    let s = try makeScratch()
    defer { s.remove() }
    #expect(
      VaultMover.retire(VaultMover.Endpoint(databasePath: s.path("none/vault.sqlite"), highWaterURL: nil))
        == nil)
  }
}
