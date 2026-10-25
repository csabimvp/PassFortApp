import Foundation
import Testing

@testable import PassFortVault

/// Settling a conflict copy (`m5-sync.md` A.11, `VaultRepository.resolveConflict`): one commit on
/// the device that resolves it, and every device converges on the result.
struct SyncConflictResolutionTests {
  /// X with one conflict copy on both A and B: A's older edit lost to B's newer one.
  private func conflicted(_ world: SyncWorld) async throws -> (
    a: SyncDevice, b: SyncDevice, original: UUID, copy: UUID
  ) {
    let (a, vaultID) = try await world.enableA()
    let x = try await a.repo.create(AccountPayload(title: "X", password: "first"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    world.clock.advance()
    _ = try await a.repo.update(id: x.id) { $0.password = "A's" }
    world.clock.advance()
    _ = try await b.repo.update(id: x.id) { $0.password = "B's" }
    for device in [a, b, a] { try await device.engine.run() }

    let copy = try #require(try await world.copies(of: x.id, on: a).first)
    #expect(copy.payload.password == "A's")
    return (a, b, x.id, copy.id)
  }

  @Test func keepingTheCopyMovesItsPayloadOntoTheOriginalEverywhere() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, b, original, copy) = try await conflicted(world)

    try await a.repo.resolveConflict(copy: copy, .keepCopy)
    for device in [a, b, a] { try await device.engine.run() }

    for device in [a, b] {
      let kept = try #require(try await device.repo.account(id: original))
      #expect(kept.payload.password == "A's")
      #expect(kept.payload.conflictOf == nil)
      #expect(kept.payload.passwordHistory.first?.password == "B's", "the replaced value is kept")
      #expect(
        kept.payload.revisionHistory.first?.changed.contains("kept the conflicting copy") == true)
      #expect(try await device.repo.account(id: copy)?.isDeleted ?? true)
      #expect(try await world.copies(of: original, on: device).allSatisfy(\.isDeleted))
      try await world.verify(device)
    }
    #expect(try await a.repo.allAccounts() == b.repo.allAccounts())
  }

  @Test func keepingTheOriginalDeletesTheCopyEverywhere() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, b, original, copy) = try await conflicted(world)

    try await b.repo.resolveConflict(copy: copy, .keepOriginal)
    for device in [b, a] { try await device.engine.run() }

    for device in [a, b] {
      #expect(try await device.repo.account(id: original)?.payload.password == "B's")
      #expect(try await device.repo.account(id: copy)?.isDeleted ?? true)
      try await world.verify(device)
    }
  }

  @Test func keepingBothMakesTheCopyAnOrdinaryAccount() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, b, original, copy) = try await conflicted(world)

    try await a.repo.resolveConflict(copy: copy, .keepBoth)
    for device in [a, b] { try await device.engine.run() }

    for device in [a, b] {
      let kept = try #require(try await device.repo.account(id: copy))
      #expect(!kept.isDeleted)
      #expect(kept.payload.conflictOf == nil)
      #expect(kept.payload.password == "A's")
      #expect(try await device.repo.account(id: original)?.payload.password == "B's")
      #expect(try await device.repo.summaries().allSatisfy { !$0.isConflict })
      try await world.verify(device)
    }
  }

  @Test func keepingTheCopyOfADeletedRecordKeepsTheEdit() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, vaultID) = try await world.enableA()
    let y = try await a.repo.create(AccountPayload(title: "Y"))
    try await a.engine.run()
    let b = try await world.join("B", vaultID)
    try await b.engine.run()

    world.clock.advance()
    _ = try await b.repo.update(id: y.id) { $0.notes = "B's edit" }
    world.clock.advance()
    try await a.repo.delete(id: y.id)  // newer: the delete wins, the edit becomes a copy
    for device in [a, b, a] { try await device.engine.run() }
    let copy = try #require(try await world.copies(of: y.id, on: b).first)

    try await b.repo.resolveConflict(copy: copy.id, .keepCopy)
    for device in [b, a] { try await device.engine.run() }

    for device in [a, b] {
      let live = try await device.repo.allAccounts().filter { !$0.isDeleted }
      #expect(live.map(\.payload.notes) == ["B's edit"], "exactly one live Y, with the edit")
      #expect(live.allSatisfy { $0.payload.conflictOf == nil })
      try await world.verify(device)
    }
  }

  @Test func anOrdinaryAccountIsNotACopy() async throws {
    let world = try SyncWorld()
    defer { world.cleanUp() }
    let (a, _) = try await world.enableA()
    let plain = try await a.repo.create(AccountPayload(title: "Plain"))

    await #expect(throws: VaultError.notFound) {
      try await a.repo.resolveConflict(copy: plain.id, .keepBoth)
    }
  }
}
