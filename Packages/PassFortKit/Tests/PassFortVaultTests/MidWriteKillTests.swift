import Foundation
import PassFortCrypto
import Testing

@testable import PassFortVault

/// The §8.2 kill test: a real child process (`pf-killtest`) `_exit`s mid-write at
/// each fault point; the parent then reopens the vault and asserts the row and the
/// manifest MAC never diverged. `_exit` -- not `exit`, not a thrown error -- so no
/// cleanup runs, exactly like a power cut.
@Suite struct MidWriteKillTests {

  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }
  private let device = UUID(uuid: (5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5))
  private let password = Data("killtest".utf8)

  /// The built `pf-killtest`. `PF_KILLTEST_BIN` wins if set (CI); otherwise
  /// `<package>/.build/debug/pf-killtest` via the source path.
  private func helperExecutable() throws -> URL {
    let candidate: URL
    if let override = ProcessInfo.processInfo.environment["PF_KILLTEST_BIN"] {
      candidate = URL(fileURLWithPath: override)
    } else {
      candidate =
        URL(fileURLWithPath: #filePath)  // Tests/PassFortVaultTests/MidWriteKillTests.swift
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/debug/pf-killtest")
    }
    try #require(
      FileManager.default.isExecutableFile(atPath: candidate.path(percentEncoded: false)),
      "pf-killtest not found at \(candidate.path) -- run `swift build` first")
    return candidate
  }

  private func kill(_ helper: URL, databasePath: String, at point: FaultPoint) throws -> Int32 {
    let process = Process()
    process.executableURL = helper
    process.arguments = [databasePath, point.rawValue]
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
  }

  /// Set up a 2-record vault and then **release every connection** (the helper is a
  /// separate process; the parent must not hold the file open). Returns the target
  /// record and the vault version after setup.
  private func setUpVault(databasePath: String) async throws -> (target: UUID, version: UInt64) {
    let repo = try await Vault.create(
      databasePath: databasePath, password: password, params: fastParams, deviceID: device)
    _ = try await repo.create(AccountPayload(title: "one", password: "p1"))
    _ = try await repo.create(AccountPayload(title: "two", password: "p2"))
    // Lowest uuid -- the record the helper picks with `summaries().first`.
    let target = try #require(await repo.summaries().first).id
    return (target, 2)  // create seeds v0, then two writes
  }

  private func vaultVersion(databasePath: String) async throws -> UInt64 {
    try await VaultDatabase(path: databasePath).dbQueue.read { try VaultMeta.readVaultVersion($0) }
  }

  @Test(arguments: FaultPoint.allCases)
  func rowAndManifestNeverDiverge(_ point: FaultPoint) async throws {
    let helper = try helperExecutable()
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-kill-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let databasePath = dir.appending(path: "vault.sqlite").path(percentEncoded: false)

    let (target, versionBefore) = try await setUpVault(databasePath: databasePath)

    let status = try kill(helper, databasePath: databasePath, at: point)
    #expect(status == 1, "expected _exit(1) from the fault hook, got \(status)")

    // Reopen with a fresh session -- must verify (this is `verifyAtUnlock` + the
    // sidecar check). A throw here is the bug the test exists to catch.
    let reopened = try await Vault.unlock(
      databasePath: databasePath, password: password, deviceID: device)

    let summaries = try await reopened.summaries()
    #expect(summaries.count == 2)  // no phantom row, no lost row

    let record = try #require(await reopened.account(id: target))
    let versionAfter = try await vaultVersion(databasePath: databasePath)

    switch point {
    case .afterRowWrite, .afterMetaWrite:
      // The transaction never committed: everything rolled back.
      #expect(versionAfter == versionBefore)
      #expect(record.version == 1)
      #expect(record.payload.notes == nil)
      #expect(try HighWaterMark(sidecarFor: databasePath).read() == versionBefore)

    case .afterCommit:
      // The transaction committed; only the sidecar bump was lost. Reopen repaired
      // it forward.
      #expect(versionAfter == versionBefore + 1)
      #expect(record.version == 2)
      #expect(record.payload.notes == "killed at afterCommit")
      #expect(try HighWaterMark(sidecarFor: databasePath).read() == versionAfter)
    }
  }
}
