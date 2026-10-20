import Foundation
import PassFortCrypto
import PassFortVault
import Testing

@testable import PassFort

/// The restore flow without UI: real vaults and backups in temp directories, hooks that record the
/// order things happen in.
@MainActor
struct RestoreModelTests {

  private let password = Data("correct horse".utf8)
  private let fastParams = KdfParameters(
    kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))

  /// Records the hook calls, and what the disk looked like when `reload` ran.
  private final class Recorder {
    var events: [String] = []
    var versionOnDiskAtReload: UInt64?
    var refusal: String?
    let livePath: String

    init(livePath: String) { self.livePath = livePath }

    var hooks: RestoreModel.Hooks {
      RestoreModel.Hooks(
        begin: { [self] in
          events.append("begin")
          return refusal
        },
        releaseVault: { [self] in events.append("release") },
        reload: { [self] in
          events.append("reload")
          versionOnDiskAtReload = VaultBackup.inspect(URL(fileURLWithPath: livePath))?.vaultVersion
        },
        end: { [self] in events.append("end") })
    }
  }

  private struct Scratch {
    let dir: URL
    func path(_ name: String) -> String { dir.appending(path: name).path(percentEncoded: false) }
    func url(_ name: String) -> URL { dir.appending(path: name) }
    func remove() { try? FileManager.default.removeItem(at: dir) }
  }

  private func makeScratch() throws -> Scratch {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-restore-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return Scratch(dir: dir)
  }

  /// A vault with `accounts` accounts, closed on return.
  private func makeVault(at path: String, accounts: Int) async throws {
    let repo = try await Vault.create(
      databasePath: path, password: password, params: fastParams, deviceID: VaultService.deviceID)
    for i in 0..<accounts {
      _ = try await repo.create(AccountPayload(title: "acct-\(i)", username: "u", password: "p"))
    }
  }

  private func addAccount(at path: String, title: String) async throws {
    let repo = try await Vault.unlock(
      databasePath: path, password: password, deviceID: VaultService.deviceID)
    _ = try await repo.create(AccountPayload(title: title, username: "u", password: "p"))
  }

  private func accountCount(at path: String) async throws -> Int {
    try await Vault.unlock(databasePath: path, password: password, deviceID: VaultService.deviceID)
      .summaries().filter { !$0.isDeleted }.count
  }

  /// A named backup of the vault at `path`, in `s.dir/nas`, as the backup feature would write it.
  @discardableResult
  private func makeBackup(of path: String, in s: Scratch, at date: Date) throws -> URL {
    let nas = s.url("nas")
    try FileManager.default.createDirectory(at: nas, withIntermediateDirectories: true)
    let info = try #require(VaultBackup.inspect(URL(fileURLWithPath: path)))
    let file = nas.appending(path: VaultBackup.fileName(vaultID: info.vaultID, at: date))
    try VaultBackup.create(databasePath: path, to: file)
    return file
  }

  // MARK: - Choosing

  @Test func aFileThatIsNotABackupIsRejected() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    try Data("junk".utf8).write(to: s.url("junk.sqlite"))
    let model = RestoreModel(databasePath: s.path("vault.sqlite"))

    await model.choose(s.url("junk.sqlite"))

    #expect(model.step == .failed(AppError.notABackup.message))
  }

  @Test func choosingDescribesTheBackupAndTheCurrentVault() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    try await makeVault(at: live, accounts: 1)
    let taken = Date(timeIntervalSince1970: 1_700_000_000)
    let backup = try makeBackup(of: live, in: s, at: taken)
    try await addAccount(at: live, title: "later")
    let model = RestoreModel(databasePath: live)

    await model.choose(backup)

    guard case .confirming(let candidate) = model.step else {
      Issue.record("expected .confirming, got \(model.step)")
      return
    }
    #expect(candidate.madeAt == taken)
    #expect(candidate.fileName == backup.lastPathComponent)
    #expect(!candidate.isDifferentVault)
    #expect(candidate.isOlderThanCurrent)
    #expect(candidate.current != nil)
  }

  @Test func cancellingDiscardsTheStagedCopy() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    try await makeVault(at: live, accounts: 1)
    let backup = try makeBackup(of: live, in: s, at: .now)
    let model = RestoreModel(databasePath: live)
    await model.choose(backup)
    guard case .confirming(let candidate) = model.step else {
      Issue.record("expected .confirming")
      return
    }
    #expect(FileManager.default.fileExists(atPath: candidate.staged.local.path(percentEncoded: false)))

    model.cancel()

    #expect(model.step == .idle)
    #expect(!FileManager.default.fileExists(atPath: candidate.staged.local.path(percentEncoded: false)))
  }

  // MARK: - Confirming

  @Test func confirmReleasesTheVaultThenSwapsThenReloads() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    try await makeVault(at: live, accounts: 2)
    let backup = try makeBackup(of: live, in: s, at: .now)
    let backupVersion = try #require(VaultBackup.inspect(backup)).vaultVersion
    try await addAccount(at: live, title: "added-after-backup")
    #expect(try await accountCount(at: live) == 3)

    let model = RestoreModel(databasePath: live)
    let recorder = Recorder(livePath: live)
    await model.choose(backup)
    await model.confirm(recorder.hooks)

    #expect(recorder.events == ["begin", "release", "reload", "end"])
    // By the time the app re-reads the disk, the swap has already happened.
    #expect(recorder.versionOnDiskAtReload == backupVersion)

    guard case .restored(let previous) = model.step, let kept = previous else {
      Issue.record("expected .restored with a safety copy, got \(model.step)")
      return
    }
    // The next unlock sees an older file than the anti-rollback mark: the normal restore prompt.
    try HighWaterMark(sidecarFor: live).reset()
    #expect(try await accountCount(at: live) == 2)
    // Nothing destroyed: the replaced vault is still there with its third account.
    #expect(try await accountCount(at: s.path(kept)) == 3)
  }

  @Test func theStagedCopyIsGoneAfterwards() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    try await makeVault(at: live, accounts: 1)
    let backup = try makeBackup(of: live, in: s, at: .now)
    let model = RestoreModel(databasePath: live)
    await model.choose(backup)
    guard case .confirming(let candidate) = model.step else { return }

    await model.confirm(Recorder(livePath: live).hooks)

    #expect(!FileManager.default.fileExists(atPath: candidate.staged.local.path(percentEncoded: false)))
  }

  @Test func aRefusalChangesNothingAndDoesNotEndWhatNeverBegan() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("vault.sqlite")
    try await makeVault(at: live, accounts: 2)
    let backup = try makeBackup(of: live, in: s, at: .now)
    try await addAccount(at: live, title: "newer")

    let model = RestoreModel(databasePath: live)
    let recorder = Recorder(livePath: live)
    recorder.refusal = "A backup is running. Try again in a moment."
    await model.choose(backup)
    await model.confirm(recorder.hooks)

    #expect(model.step == .failed("A backup is running. Try again in a moment."))
    #expect(recorder.events == ["begin"])
    #expect(try await accountCount(at: live) == 3)  // untouched
  }

  @Test func aDifferentVaultIsFlaggedAndReplacedOnceConfirmed() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let live = s.path("a.sqlite")
    let other = s.path("b.sqlite")
    try await makeVault(at: live, accounts: 1)
    try await makeVault(at: other, accounts: 3)
    let backupOfOther = try makeBackup(of: other, in: s, at: .now)

    let model = RestoreModel(databasePath: live)
    await model.choose(backupOfOther)
    guard case .confirming(let candidate) = model.step else {
      Issue.record("expected .confirming")
      return
    }
    #expect(candidate.isDifferentVault)

    await model.confirm(Recorder(livePath: live).hooks)

    guard case .restored = model.step else {
      Issue.record("expected .restored, got \(model.step)")
      return
    }
    try HighWaterMark(sidecarFor: live).reset()
    #expect(try await accountCount(at: live) == 3)
  }

  @Test func aFreshMacWithNoVaultJustGetsTheBackup() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let source = s.path("source.sqlite")
    try await makeVault(at: source, accounts: 2)
    let backup = try makeBackup(of: source, in: s, at: .now)
    let live = s.path("fresh/PassFort/vault.sqlite")

    let model = RestoreModel(databasePath: live)
    await model.choose(backup)
    guard case .confirming(let candidate) = model.step else {
      Issue.record("expected .confirming")
      return
    }
    #expect(candidate.current == nil)
    #expect(!candidate.isDifferentVault)

    await model.confirm(Recorder(livePath: live).hooks)

    #expect(model.step == .restored(previousVault: nil))
    #expect(try await accountCount(at: live) == 2)
  }

  @Test func confirmingWithoutAChosenBackupDoesNothing() async throws {
    let s = try makeScratch()
    defer { s.remove() }
    let recorder = Recorder(livePath: s.path("vault.sqlite"))
    let model = RestoreModel(databasePath: s.path("vault.sqlite"))

    await model.confirm(recorder.hooks)

    #expect(recorder.events.isEmpty)
    #expect(model.step == .idle)
  }
}
