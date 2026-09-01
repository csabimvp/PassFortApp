import Foundation
import PassFortCrypto
import Testing

@testable import PassFortVault

@Suite struct PlaintextExportTests {

  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }
  private let device = UUID(uuid: (2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2))

  private func freshRepo() async throws -> (dir: URL, repo: VaultRepository) {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-exp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appending(path: "vault.sqlite").path(percentEncoded: false)
    let repo = try await Vault.create(
      databasePath: path, password: Data("pw".utf8), params: fastParams, deviceID: device)
    return (dir, repo)
  }

  @Test func confirmationGateRejectsAnythingButTheExactPhrase() async throws {
    let (dir, repo) = try await freshRepo()
    defer { try? FileManager.default.removeItem(at: dir) }

    #expect(throws: VaultError.exportNotConfirmed) {
      try ExportConfirmation(phrase: "export plaintext")
    }
    #expect(throws: VaultError.exportNotConfirmed) {
      try ExportConfirmation(phrase: "EXPORT PLAINTEXT ")
    }
    #expect(throws: VaultError.exportNotConfirmed) { try ExportConfirmation(phrase: "") }

    let ok = try ExportConfirmation(phrase: ExportConfirmation.phrase)
    _ = try await repo.exportPlaintext(confirmed: ok)  // does not throw
  }

  @Test func exportDecryptsEveryFieldAndRoundTripsThroughJSON() async throws {
    let (dir, repo) = try await freshRepo()
    defer { try? FileManager.default.removeItem(at: dir) }

    _ = try await repo.create(
      AccountPayload(
        title: "GitHub", username: "me", password: "s3cret", notes: "2fa in authenticator"))
    let doomed = try await repo.create(AccountPayload(title: "old", password: "gone"))
    try await repo.delete(id: doomed.id)

    let export = try await repo.exportPlaintext(
      confirmed: try ExportConfirmation(phrase: ExportConfirmation.phrase))

    #expect(export.schemaVersion == 1)
    #expect(export.accounts.count == 2)  // tombstone included
    #expect(
      export.accounts.contains { $0.payload.title == "GitHub" && $0.payload.password == "s3cret" })
    #expect(export.accounts.contains { $0.id == doomed.id && $0.isDeleted })

    let json = try export.jsonData()
    let text = try #require(String(data: json, encoding: .utf8))
    #expect(text.contains("\"schema_version\""))
    #expect(text.contains("\"vault_uuid\""))
    #expect(text.contains("\"is_deleted\""))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let reparsed = try decoder.decode(PlaintextExport.self, from: json)
    #expect(reparsed.accounts.count == export.accounts.count)
    #expect(reparsed.vaultUUID == export.vaultUUID)
  }

  @Test func vaultUUIDIsStableAcrossReopens() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pf-exp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appending(path: "vault.sqlite").path(percentEncoded: false)

    let confirm = try ExportConfirmation(phrase: ExportConfirmation.phrase)
    let repo = try await Vault.create(
      databasePath: path, password: Data("pw".utf8), params: fastParams, deviceID: device)
    let first = try await repo.exportPlaintext(confirmed: confirm).vaultUUID

    let reopened = try await Vault.unlock(
      databasePath: path, password: Data("pw".utf8), deviceID: device)
    let second = try await reopened.exportPlaintext(confirmed: confirm).vaultUUID
    #expect(first == second)
  }
}
