import Foundation
import Testing

@testable import PassFortCrypto

@Suite struct BoundaryTests {

  // MARK: - M0 seam probe

  @Test func echoRoundTripsArbitraryBytes() throws {
    let input = Data((0..<512).map { UInt8($0 & 0xFF) })
    #expect(try echo(input) == input)
  }

  @Test func echoHandlesEmptyInput() throws {
    #expect(try echo(Data()) == Data())
  }

  // MARK: - M1 VaultSession

  /// Cheap Argon2 so the suite stays fast; `calibrateProducesUsableParameters`
  /// exercises the real measurement path.
  private var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }

  private func openFreshVault(password: Data) throws -> VaultSession {
    let header = try VaultSession.create(password: password, params: fastParams)
    return try VaultSession.open(header: header, password: password)
  }

  @Test func sealThenOpenReturnsThePlaintext() async throws {
    let session = try openFreshVault(password: Data("correct horse".utf8))
    let id = UUID()
    let plaintext = Data("battery staple".utf8)

    let sealed = try await session.seal(recordID: id, version: 3, schema: 2, plaintext: plaintext)
    let recovered = try await session.open(recordID: id, version: 3, schema: 2, sealed: sealed)
    #expect(recovered == plaintext)
  }

  @Test func emptyAndLargePlaintextRoundTrip() async throws {
    let session = try openFreshVault(password: Data("pw".utf8))
    let id = UUID()

    let emptySealed = try await session.seal(
      recordID: id, version: 1, schema: 1, plaintext: Data())
    let reopened = try await session.open(
      recordID: id, version: 1, schema: 1, sealed: emptySealed)
    #expect(reopened == Data())

    let big = Data((0..<200_000).map { UInt8(($0 &* 31 &+ 7) & 0xFF) })
    let bigSealed = try await session.seal(recordID: id, version: 1, schema: 1, plaintext: big)
    #expect(try await session.open(recordID: id, version: 1, schema: 1, sealed: bigSealed) == big)
  }

  @Test func wrongPasswordThrowsAuthFailed() throws {
    let header = try VaultSession.create(password: Data("right".utf8), params: fastParams)
    #expect(throws: PassFortError.authFailed) {
      try VaultSession.open(header: header, password: Data("wrong".utf8))
    }
  }

  @Test func tamperedHeaderThrowsAuthFailed() throws {
    var header = try VaultSession.create(password: Data("pw".utf8), params: fastParams)
    header[8] ^= 0x01  // a vault_uuid byte -- inside the wrap AAD
    #expect(throws: PassFortError.authFailed) {
      try VaultSession.open(header: header, password: Data("pw".utf8))
    }
  }

  @Test func shortHeaderThrowsBadInput() throws {
    #expect(throws: PassFortError.badInput) {
      try VaultSession.open(header: Data([0x50, 0x46, 0x56]), password: Data("pw".utf8))
    }
  }

  @Test func wrongRecordIdentityThrowsAuthFailed() async throws {
    let session = try openFreshVault(password: Data("pw".utf8))
    let id = UUID()
    let sealed = try await session.seal(
      recordID: id, version: 1, schema: 1, plaintext: Data("x".utf8))

    await #expect(throws: PassFortError.authFailed) {
      try await session.open(recordID: id, version: 2, schema: 1, sealed: sealed)
    }
    await #expect(throws: PassFortError.authFailed) {
      try await session.open(recordID: UUID(), version: 1, schema: 1, sealed: sealed)
    }
  }

  @Test func rewrapChangesThePasswordButKeepsTheDEK() async throws {
    let old = Data("old".utf8)
    let new = Data("new".utf8)
    let session = try openFreshVault(password: old)

    let id = UUID()
    let plaintext = Data("keep me".utf8)
    let sealed = try await session.seal(recordID: id, version: 1, schema: 1, plaintext: plaintext)

    let newHeader = try await session.rewrap(newPassword: new)
    #expect(throws: PassFortError.authFailed) {
      try VaultSession.open(header: newHeader, password: old)
    }

    let reopened = try VaultSession.open(header: newHeader, password: new)
    let recovered = try await reopened.open(recordID: id, version: 1, schema: 1, sealed: sealed)
    #expect(recovered == plaintext)  // same DEK -> the old record still opens
  }

  @Test func calibrateProducesUsableParameters() throws {
    let params = try VaultSession.calibrate(targetMs: 1)
    #expect(params.kdfID == 1)
    #expect(params.iterations == 3)
    #expect(params.parallelism == 4)
    #expect(params.memoryKiB >= 64 * 1024)
    #expect(params.salt.count == 16)
    #expect(params.salt.contains { $0 != 0 })

    // The measured params actually open a vault they created.
    let header = try VaultSession.create(password: Data("pw".utf8), params: params)
    _ = try VaultSession.open(header: header, password: Data("pw".utf8))
  }

  // MARK: - M1 ManifestBuilder

  @Test func manifestBuilderIsDeterministicAndSingleShot() async throws {
    let session = try openFreshVault(password: Data("pw".utf8))
    let rows: [(UUID, UInt64, Data)] = [
      (UUID(), 1, Data(repeating: 0xAA, count: 48)),
      (UUID(), 7, Data(repeating: 0xBB, count: 61)),
    ]

    func computeMac(vaultVersion: UInt64) async throws -> Data {
      let builder = try await session.makeManifestBuilder(vaultVersion: vaultVersion)
      for (id, version, sealed) in rows {
        try builder.update(recordID: id, version: version, sealed: sealed)
      }
      return try builder.finish()
    }

    let mac = try await computeMac(vaultVersion: 1)
    #expect(mac.count == 32)
    #expect(try await computeMac(vaultVersion: 1) == mac)
    #expect(try await computeMac(vaultVersion: 2) != mac)  // vault_version is folded in
  }

  @Test func manifestBuilderThrowsAfterFinish() async throws {
    let session = try openFreshVault(password: Data("pw".utf8))
    let builder = try await session.makeManifestBuilder(vaultVersion: 1)
    try builder.update(recordID: UUID(), version: 1, sealed: Data(repeating: 1, count: 48))
    _ = try builder.finish()

    #expect(throws: PassFortError.self) {
      try builder.update(recordID: UUID(), version: 2, sealed: Data(repeating: 1, count: 48))
    }
    #expect(throws: PassFortError.self) { _ = try builder.finish() }
  }
}
