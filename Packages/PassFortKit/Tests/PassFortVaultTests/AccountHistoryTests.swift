import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

/// Per-account password history + revision history (§7.2 / §7.7). All behaviour
/// lives in `VaultRepository`'s write path; these drive a real repo.
@Suite struct AccountHistoryTests {

  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }
  private let device = UUID(uuid: (9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9))

  private struct Harness {
    let dir: URL
    let path: String
    let header: Data
    let password: Data
    let repo: VaultRepository
  }

  private func makeHarness() async throws -> Harness {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-hist-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appending(path: "vault.sqlite").path(percentEncoded: false)
    let password = Data("history test".utf8)
    let header = try VaultSession.create(password: password, params: fastParams)
    let repo = try await VaultRepository.bootstrap(
      database: try VaultDatabase(path: path),
      session: try VaultSession.open(header: header, password: password),
      header: header, deviceID: device, highWater: HighWaterMark(sidecarFor: path))
    return Harness(dir: dir, path: path, header: header, password: password, repo: repo)
  }

  private func reopen(_ h: Harness) async throws -> VaultRepository {
    try await VaultRepository.open(
      database: try VaultDatabase(path: h.path),
      session: try VaultSession.open(header: h.header, password: h.password),
      deviceID: device, highWater: HighWaterMark(sidecarFor: h.path))
  }

  // MARK: - Password history

  @Test func aPasswordChangeKeepsTheOldValue() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "Bank", password: "first"))
    #expect(made.payload.passwordHistory.isEmpty)
    #expect(made.payload.passwordChangedAt != nil)  // seeded at create

    let edited = try await h.repo.update(id: made.id) { $0.password = "second" }
    #expect(edited.payload.password == "second")
    #expect(edited.payload.passwordHistory.map(\.password) == ["first"])

    let again = try await h.repo.update(id: made.id) { $0.password = "third" }
    #expect(again.payload.passwordHistory.map(\.password) == ["second", "first"])  // newest first
  }

  @Test func aNonPasswordEditLeavesPasswordHistoryAlone() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "Bank", password: "pw"))
    let edited = try await h.repo.update(id: made.id) { $0.notes = "note" }
    #expect(edited.payload.passwordHistory.isEmpty)
  }

  @Test func passwordHistoryIsCapped() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "Bank", password: "pw0"))
    for index in 1...(VaultRepository.passwordHistoryLimit + 6) {
      _ = try await h.repo.update(id: made.id) { $0.password = "pw\(index)" }
    }
    let final = try #require(await h.repo.account(id: made.id))
    let cap = VaultRepository.passwordHistoryLimit
    #expect(final.payload.passwordHistory.count == cap)
    #expect(final.payload.passwordHistory.first?.password == "pw\(cap + 5)")
  }

  // MARK: - Revision history

  @Test func createSeedsACreatedRevision() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "GitHub"))
    #expect(made.payload.revisionHistory.map(\.version) == [1])
    #expect(made.payload.revisionHistory.first?.changed == ["created"])
  }

  @Test func everyEditRecordsWhatChanged() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "GitHub"))
    _ = try await h.repo.update(id: made.id) { $0.username = "me" }
    let v3 = try await h.repo.update(id: made.id) {
      $0.password = "s3cret"
      $0.notes = "2fa on"
    }

    let versions = v3.payload.revisionHistory.map(\.version)
    #expect(versions == [3, 2, 1])  // newest first
    #expect(Set(v3.payload.revisionHistory[0].changed) == ["password", "notes"])
    #expect(v3.payload.revisionHistory[1].changed == ["username"])
  }

  @Test func aNoOpEditRecordsNoRevision() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "GitHub"))
    let after = try await h.repo.update(id: made.id) { _ in }  // touches nothing
    #expect(after.version == 2)  // the version still bumps (existing behaviour)
    #expect(after.payload.revisionHistory.map(\.version) == [1])  // ...but no new entry
  }

  @Test func deleteRecordsADeletedRevision() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "temp"))
    try await h.repo.delete(id: made.id)

    let tombstone = try #require(await h.repo.account(id: made.id))
    #expect(tombstone.isDeleted)
    #expect(tombstone.payload.revisionHistory.first?.changed == ["deleted"])
    #expect(tombstone.payload.revisionHistory.first?.version == 2)
  }

  @Test func revisionHistoryIsCapped() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "GitHub"))
    for index in 1...(VaultRepository.revisionHistoryLimit + 10) {
      _ = try await h.repo.update(id: made.id) { $0.notes = "note \(index)" }
    }
    let final = try #require(await h.repo.account(id: made.id))
    let cap = VaultRepository.revisionHistoryLimit
    #expect(final.payload.revisionHistory.count == cap)
    #expect(final.payload.revisionHistory.first?.version == UInt64(cap + 11))
  }

  @Test func historySurvivesAReopen() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "GitHub", password: "a"))
    _ = try await h.repo.update(id: made.id) { $0.password = "b" }

    let reopened = try await reopen(h)
    let fetched = try #require(await reopened.account(id: made.id))
    #expect(fetched.payload.passwordHistory.map(\.password) == ["a"])
    #expect(fetched.payload.revisionHistory.map(\.version) == [2, 1])
  }

  // MARK: - last_updated

  @Test func lastUpdatedTracksTheWrite() async throws {
    let h = try await makeHarness()
    defer { try? FileManager.default.removeItem(at: h.dir) }

    let made = try await h.repo.create(AccountPayload(title: "GitHub"))
    let createdStamp = made.lastUpdated
    #expect(abs(createdStamp.timeIntervalSinceNow) < 5)

    try await Task.sleep(for: .milliseconds(1100))  // HLC persists whole millis
    let edited = try await h.repo.update(id: made.id) { $0.notes = "later" }
    #expect(edited.lastUpdated > createdStamp)
  }
}
