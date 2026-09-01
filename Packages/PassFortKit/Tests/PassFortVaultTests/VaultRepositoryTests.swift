import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

@Suite struct VaultRepositoryTests {

  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }

  private let device = UUID(uuid: (7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7))

  private struct Harness {
    let dir: URL
    let path: String
    let header: Data
    let password: Data
    let repo: VaultRepository

    func newSession() throws -> VaultSession {
      try VaultSession.open(header: header, password: password)
    }

    var database: VaultDatabase { get throws { try VaultDatabase(path: path) } }
    var highWater: HighWaterMark { HighWaterMark(sidecarFor: path) }
  }

  private func makeHarness() async throws -> Harness {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-repo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appending(path: "vault.sqlite").path(percentEncoded: false)

    let password = Data("correct horse".utf8)
    let header = try VaultSession.create(password: password, params: fastParams)
    let database = try VaultDatabase(path: path)
    let session = try VaultSession.open(header: header, password: password)
    let repo = try await VaultRepository.bootstrap(
      database: database, session: session, header: header, deviceID: device,
      highWater: HighWaterMark(sidecarFor: path))

    return Harness(dir: dir, path: path, header: header, password: password, repo: repo)
  }

  private func reopen(_ h: Harness) async throws -> VaultRepository {
    try await VaultRepository.open(
      database: try h.database, session: try h.newSession(), deviceID: device,
      highWater: h.highWater)
  }

  // MARK: - CRUD

  @Test func createRoundTripsThroughAccount() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(
      AccountPayload(title: "GitHub", username: "me", password: "s3cret"))
    #expect(made.version == 1)

    let fetched = try await h.repo.account(id: made.id)
    #expect(fetched?.payload.title == "GitHub")
    #expect(fetched?.payload.password == "s3cret")
    #expect(fetched?.version == 1)
  }

  @Test func updateBumpsVersionAndResealsAndStaysVerifiable() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "GitLab", password: "old"))
    let edited = try await h.repo.update(id: made.id) { $0.password = "rotated" }
    #expect(edited.version == 2)
    #expect(edited.payload.password == "rotated")

    // A fresh session + repo re-verifies the whole vault from disk.
    _ = try await reopen(h)
    let fetched = try await h.repo.account(id: made.id)
    #expect(fetched?.payload.password == "rotated")
    #expect(fetched?.version == 2)
  }

  @Test func summariesCoverEveryRowAndCarryNoSecret() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    _ = try await h.repo.create(AccountPayload(title: "one", username: "a"))
    _ = try await h.repo.create(AccountPayload(title: "two", username: "b"))

    let summaries = try await h.repo.summaries()
    #expect(Set(summaries.map(\.title)) == ["one", "two"])
  }

  // MARK: - Tombstones

  @Test func deleteHidesFromLiveReadsButStillVerifies() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "temp"))
    try await h.repo.delete(id: made.id)

    let fetched = try await h.repo.account(id: made.id)
    #expect(fetched?.isDeleted == true)  // still there, flagged
    await #expect(throws: VaultError.notFound) {
      try await h.repo.update(id: made.id) { $0.title = "resurrected" }
    }

    _ = try await reopen(h)  // manifest still verifies with the tombstone in it
  }

  @Test func compactRemovesTombstonesAndKeepsTheManifestConsistent() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let keep = try await h.repo.create(AccountPayload(title: "keep"))
    let drop = try await h.repo.create(AccountPayload(title: "drop"))
    try await h.repo.delete(id: drop.id)
    try await h.repo.compact()

    #expect(try await h.repo.account(id: drop.id) == nil)
    #expect(try await h.repo.account(id: keep.id) != nil)
    _ = try await reopen(h)
  }

  @Test func compactIsANoOpWithNothingToPurge() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    _ = try await h.repo.create(AccountPayload(title: "solo"))
    let before = try await h.database.dbQueue.read { try VaultMeta.readVaultVersion($0) }
    try await h.repo.compact()
    let after = try await h.database.dbQueue.read { try VaultMeta.readVaultVersion($0) }
    #expect(before == after)  // no version bump, no wasted re-MAC
  }

  // MARK: - Anti-rollback

  @Test func restoringAnOlderDatabaseFileIsRejectedAtOpen() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    _ = try await h.repo.create(AccountPayload(title: "a"))
    _ = try await h.repo.create(AccountPayload(title: "b"))

    // Snapshot the file at version 2 (checkpoint the WAL so it's all in the .sqlite).
    try await h.database.dbQueue.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
    }
    let backup = h.dir.appending(path: "backup.sqlite")
    try FileManager.default.copyItem(atPath: h.path, toPath: backup.path(percentEncoded: false))

    let target = try #require(await h.repo.summaries().first).id
    _ = try await h.repo.update(id: target) { $0.notes = "moved on to v3" }

    // Roll the database back to the v2 snapshot; the high-water sidecar still says v3.
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(atPath: h.path + suffix)
    }
    try FileManager.default.copyItem(atPath: backup.path(percentEncoded: false), toPath: h.path)

    await #expect(throws: VaultManifest.Failure.rollbackDetected(vaultVersion: 2, highWater: 3)) {
      _ = try await reopen(h)
    }
  }

  @Test func aFreshVaultOpensClean() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }
    _ = try await reopen(h)  // bootstrap wrote a v0 manifest over the empty set
  }
}
