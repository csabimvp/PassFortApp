import Foundation
import GRDB
import PassFortCrypto
import Testing

@testable import PassFortVault

/// `m5-sync.md` Phase 9 (A.8): a header change on one device -- recovery-key rotation, recovery,
/// a password change -- reaches the others as a pending header, adopted at their next unlock.
@Suite struct SyncHeaderTests {

  private func meta(_ device: SyncDevice) async throws
    -> (header: Data?, version: UInt64?, dirty: Bool, pending: PendingHeader?)
  {
    try await VaultDatabase(path: device.path).dbQueue.read { db in
      (
        try VaultMeta.read(db, .header), try VaultMeta.readSyncHeaderVersion(db),
        try VaultMeta.readHeaderDirty(db), try VaultMeta.readPendingHeader(db)
      )
    }
  }

  /// A and B, synced, with one record.
  private func pair(in world: SyncWorld) async throws -> (a: SyncDevice, b: SyncDevice, vault: UUID)
  {
    let (a, vaultID) = try await world.enableA()
    _ = try await a.repo.create(AccountPayload(title: "shared"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()
    return (a, b, vaultID)
  }

  // MARK: - The checkpoint

  @Test func aRotatedRecoveryKeyReachesTheOtherDeviceAtItsNextUnlock() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, b, vaultID) = try await pair(in: world)
    let before = try #require(try await meta(b).header)

    let recovery = try await a.repo.rotateRecoveryKey()
    #expect(try await meta(a).dirty, "a local header change with sync on")
    try await a.engine.run()
    #expect(try await meta(a).dirty == false)
    #expect(try await meta(a).version == 2)
    #expect(await world.server.vault(vaultID)?.headerVersion == 2)

    try await b.engine.run()
    let pending = try #require(try await meta(b).pending)
    #expect(pending.headerVersion == 2)
    #expect(try await meta(b).header == before, "nothing is adopted while unlocked")

    let relocked = try await world.unlock(b, password: world.password)
    let adopted = try await meta(relocked)
    #expect(adopted.header == (try await meta(a).header))
    #expect(adopted.header?.count == before.count + 72, "the same header plus slot 1")
    #expect(adopted.version == 2)
    #expect(adopted.pending == nil)
    #expect(adopted.dirty == false, "adopting is not a local change")
    #expect(try await relocked.repo.headerChangedElsewhere() == false)

    // The recovery key A was shown now opens B's vault too.
    _ = try VaultSession.openWithRecovery(
      header: try #require(adopted.header), recoveryKey: recovery.raw)
    try await relocked.engine.run()  // and B keeps syncing on the adopted header
    #expect(await world.server.vault(vaultID)?.headerVersion == 2)
    try await world.verify(relocked)
  }

  @Test func aRecoveryWithANewPasswordIsAdoptedWithTheNewPasswordAndFlaggedWithTheOld()
    async throws
  {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, b, _) = try await pair(in: world)
    let recovery = try await a.repo.rotateRecoveryKey()
    try await a.engine.run()
    try await b.engine.run()
    let b1 = try await world.unlock(b, password: world.password)  // adopts the two-slot header

    // A forgets its password and recovers with a new one.
    let newPassword = Data("battery staple".utf8)
    let recovered = try await Vault.recover(
      databasePath: a.path, recoveryKey: recovery, newPassword: newPassword, deviceID: a.id)
    #expect(try await meta(a).dirty)
    let a2 = world.engine(for: recovered, a.id, "A")
    try await a2.run()
    try await b1.engine.run()
    #expect(try await meta(b1).pending != nil)

    // The old password still opens B's own header: it unlocks, and the banner shows.
    let stale = try await world.unlock(b1, password: world.password)
    #expect(try await stale.repo.headerChangedElsewhere())
    #expect(try await meta(stale).pending != nil, "still waiting for the new password")
    #expect(try await stale.repo.allAccounts().count == 1)

    // The new password opens the pending header: adopted.
    let fresh = try await world.unlock(stale, password: newPassword)
    #expect(try await fresh.repo.headerChangedElsewhere() == false)
    #expect(try await meta(fresh).header == (try await recovered.header()))
    #expect(try await meta(fresh).version == (try await meta(a).version))
    await #expect(throws: PassFortError.authFailed) {
      _ = try await Vault.unlock(
        databasePath: fresh.path, password: world.password, deviceID: fresh.id)
    }
    try await world.verify(fresh, password: newPassword)
  }

  @Test func concurrentRotationsEndWithOneConflictAndTheServerHeaderPending() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, b, vaultID) = try await pair(in: world)
    _ = try await a.repo.rotateRecoveryKey()
    _ = try await b.repo.rotateRecoveryKey()
    _ = try await b.repo.create(AccountPayload(title: "made on B"))

    let start = await world.server.calls.count
    try await a.engine.run()
    await #expect(throws: SyncError.headerChangedElsewhere) { try await b.engine.run() }
    #expect(await world.calls(from: start, .putHeader) == 2, "one accepted, one refused")

    let server = try #require(await world.server.vault(vaultID))
    #expect(server.headerVersion == 2)
    let state = try await meta(b)
    #expect(state.pending == PendingHeader(headerVersion: 2, header: server.header))
    #expect(state.dirty == false, "B's change lost; it is not pushed again")
    #expect(state.version == 1)
    #expect(server.records.count == 2, "B's records still synced")

    // The next run is quiet: nothing to push, nothing new to fetch.
    let quiet = await world.server.calls.count
    try await b.engine.run()
    #expect(await world.calls(from: quiet, .putHeader) == 0)
    #expect(await world.calls(from: quiet, .header) == 0)

    let relocked = try await world.unlock(b, password: world.password)
    #expect(try await meta(relocked).header == server.header)
    #expect(try await meta(relocked).version == 2)
  }

  // MARK: - Around it

  @Test func aPasswordChangeIsPushedAndAdoptedWithTheNewPassword() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, b, _) = try await pair(in: world)
    let newPassword = Data("battery staple".utf8)
    _ = try await a.repo.changePassword(
      current: world.password, new: newPassword, issueRecoveryKey: false)
    #expect(try await meta(a).dirty)
    try await a.engine.run()
    try await b.engine.run()

    let relocked = try await world.unlock(b, password: newPassword)
    #expect(try await relocked.repo.headerChangedElsewhere() == false)
    #expect(try await meta(relocked).header == (try await meta(a).header))
  }

  @Test func withSyncOffAHeaderChangeIsNotMarkedDirty() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let header = try VaultSession.create(password: world.password, params: SyncWorld.fastParams)
    let lone = try await world.makeDevice("lone", header: header)
    _ = try await lone.repo.rotateRecoveryKey()
    #expect(try await meta(lone).dirty == false)
  }

  @Test func aHeaderChangedAgainDuringItsPushStaysDirty() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, _, vaultID) = try await pair(in: world)
    _ = try await a.repo.rotateRecoveryKey()

    let once = Once()
    await world.server.setOnRequest { call in
      if call == .putHeader, once.claim() { _ = try await a.repo.rotateRecoveryKey() }
    }
    try await a.engine.run()
    #expect(try await meta(a).dirty, "the second rotation is not on the server yet")
    #expect(try await meta(a).version == 2)

    await world.server.setOnRequest(nil)
    try await a.engine.run()
    #expect(try await meta(a).dirty == false)
    #expect(await world.server.vault(vaultID)?.header == (try await meta(a).header))
    #expect(await world.server.vault(vaultID)?.headerVersion == 3)
  }

  @Test func aPendingHeaderFromAnotherVaultIsNeverAdopted() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (_, b, _) = try await pair(in: world)
    // Same password, another vault: it opens, but it is not this vault.
    let foreign = try VaultSession.create(password: world.password, params: SyncWorld.fastParams)
    let local = try #require(try await meta(b).header)
    try await VaultDatabase(path: b.path).dbQueue.write { db in
      try VaultMeta.writePendingHeader(db, PendingHeader(headerVersion: 9, header: foreign))
    }

    let relocked = try await world.unlock(b, password: world.password)
    #expect(try await meta(relocked).header == local)
    #expect(try await relocked.repo.headerChangedElsewhere(), "still pending: the banner shows")
    #expect(try await relocked.repo.allAccounts().count == 1)
  }

  @Test func aWrongPasswordFailsWithAPendingHeaderToo() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, b, _) = try await pair(in: world)
    _ = try await a.repo.rotateRecoveryKey()
    try await a.engine.run()
    try await b.engine.run()

    await #expect(throws: PassFortError.authFailed) {
      _ = try await Vault.unlock(
        databasePath: b.path, password: Data("wrong".utf8), deviceID: b.id)
    }
    #expect(try await meta(b).pending != nil)
  }
}
