import Foundation
import Testing

@testable import PassFortVault

/// A.7, one test per row (`m5-sync.md` Phase 8). Pure: envelopes and payloads built by hand, no
/// vault, no crypto.
@Suite struct ReconcilerTests {

  private let id = UUID(uuid: (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1))
  private let here = UUID(uuid: (0xA, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
  private let there = UUID(uuid: (0xB, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

  private func local(
    version: UInt64, synced: UInt64?, deleted: Bool = false, wall: UInt64 = 100
  ) -> SealedRecord {
    SealedRecord(
      id: id, version: version, schemaVersion: 1, sealed: Data([0x01]), isDeleted: deleted,
      updatedAt: HLC(wallMillis: wall, counter: 0, deviceID: here), syncedVersion: synced,
      syncedSeq: synced.map { $0 * 10 })
  }

  private func remote(version: UInt64, deleted: Bool = false, wall: UInt64 = 100) -> RecordDTO {
    RecordDTO(
      id: id, version: version,
      hlc: HLCDTO(HLC(wallMillis: wall, counter: 0, deviceID: there)), sealed: Data([0x02]),
      isDeleted: deleted, seq: 99, writer: there)
  }

  private func payloads(_ local: String, _ remote: String) -> Reconciler.ConflictPayloads {
    .init(local: AccountPayload(title: local), remote: AccountPayload(title: remote))
  }

  // MARK: - Rows 1-4

  @Test func rule1_noLocalRowInsertsTheRemoteRecord() {
    #expect(Reconciler.decide(local: nil, remote: remote(version: 4)) == .insert)
  }

  @Test func rule2_aCleanRowIgnoresAStaleReplayAndConfirmsAnEcho() {
    let clean = local(version: 3, synced: 3)
    #expect(Reconciler.decide(local: clean, remote: remote(version: 2)) == .ignore)
    #expect(Reconciler.decide(local: clean, remote: remote(version: 3)) == .confirm)
  }

  @Test func rule3_aCleanRowFastForwardsToANewerServerVersion() {
    #expect(
      Reconciler.decide(local: local(version: 3, synced: 3), remote: remote(version: 4))
        == .fastForward)
  }

  @Test func rule4_aDirtyRowIgnoresAServerThatHasNotMovedPastItsBase() {
    let dirty = local(version: 4, synced: 3)
    #expect(!Reconciler.isConflict(local: dirty, remote: remote(version: 3)))
    #expect(Reconciler.decide(local: dirty, remote: remote(version: 3)) == .ignore)
    #expect(Reconciler.decide(local: dirty, remote: remote(version: 2)) == .ignore)
  }

  // MARK: - Row 5: both changed since the base

  @Test func rule5_aDirtyRowAndAServerPastItsBaseIsAConflict() {
    #expect(Reconciler.isConflict(local: local(version: 4, synced: 3), remote: remote(version: 4)))
    #expect(
      Reconciler.isConflict(local: local(version: 1, synced: nil), remote: remote(version: 1)))
    #expect(!Reconciler.isConflict(local: local(version: 3, synced: 3), remote: remote(version: 4)))
    #expect(!Reconciler.isConflict(local: nil, remote: remote(version: 1)))
  }

  @Test func rule5a_theSameEditOnBothSidesTakesRemoteWithNoCopy() {
    var mine = AccountPayload(title: "Bank", password: "new")
    var theirs = mine
    mine.revisionHistory = [RevisionEntry(version: 4, at: Date(), changed: ["password"])]
    mine.passwordChangedAt = Date(timeIntervalSince1970: 1)
    mine.passwordHistory = [
      PasswordHistoryEntry(password: "old", replacedAt: Date(timeIntervalSince1970: 1))
    ]
    theirs.revisionHistory = [RevisionEntry(version: 4, at: Date(), changed: ["password"])]
    theirs.passwordChangedAt = Date(timeIntervalSince1970: 2)
    theirs.passwordHistory = [
      PasswordHistoryEntry(password: "old", replacedAt: Date(timeIntervalSince1970: 2))
    ]

    // Even when the local edit is the newer one: there is nothing to keep.
    let decision = Reconciler.decide(
      local: local(version: 4, synced: 3, wall: 200), remote: remote(version: 4, wall: 100),
      payloads: .init(local: mine, remote: theirs))
    #expect(decision == .takeRemote(copyLocal: false))
  }

  @Test func rule5a_aDifferentReplacedPasswordIsNotTheSameEdit() {
    var mine = AccountPayload(title: "Bank", password: "new")
    var theirs = mine
    mine.passwordHistory = [PasswordHistoryEntry(password: "old", replacedAt: .distantPast)]
    theirs.passwordHistory = [PasswordHistoryEntry(password: "older", replacedAt: .distantPast)]
    #expect(!Reconciler.sameContent(mine, theirs))
  }

  @Test func rule5b_aNewerRemoteEditWinsAndTheLocalEditSurvivesAsACopy() {
    let decision = Reconciler.decide(
      local: local(version: 4, synced: 3, wall: 100), remote: remote(version: 4, wall: 200),
      payloads: payloads("mine", "theirs"))
    #expect(decision == .takeRemote(copyLocal: true))
  }

  @Test func rule5b_aNewerRemoteEditOverALocalDeleteKeepsNoCopy() {
    let decision = Reconciler.decide(
      local: local(version: 4, synced: 3, deleted: true, wall: 100),
      remote: remote(version: 4, wall: 200), payloads: payloads("mine", "theirs"))
    #expect(decision == .takeRemote(copyLocal: false), "the record simply survives")
  }

  @Test func rule5c_aNewerLocalEditWinsAndTheRemoteEditSurvivesAsACopy() {
    let decision = Reconciler.decide(
      local: local(version: 4, synced: 3, wall: 200), remote: remote(version: 5, wall: 100),
      payloads: payloads("mine", "theirs"))
    #expect(decision == .keepLocal(copyRemote: true))
  }

  @Test func rule5c_aNewerLocalEditOverARemoteDeleteKeepsNoCopy() {
    let decision = Reconciler.decide(
      local: local(version: 4, synced: 3, wall: 200),
      remote: remote(version: 4, deleted: true, wall: 100), payloads: payloads("mine", "theirs"))
    #expect(decision == .keepLocal(copyRemote: false))
  }

  @Test func rule5d_tombstoneBeatsEditLeavesACopy() {
    // The remote delete is newer: it wins, and the local edit is kept as a copy.
    #expect(
      Reconciler.decide(
        local: local(version: 4, synced: 3, wall: 100),
        remote: remote(version: 4, deleted: true, wall: 200), payloads: payloads("mine", "theirs"))
        == .takeRemote(copyLocal: true))
    // The local delete is newer: it wins, and the remote edit is kept as a copy.
    #expect(
      Reconciler.decide(
        local: local(version: 4, synced: 3, deleted: true, wall: 200),
        remote: remote(version: 4, wall: 100), payloads: payloads("mine", "theirs"))
        == .keepLocal(copyRemote: true))
  }

  @Test func rule5e_twoTombstonesTakeRemoteClean() {
    for wall: UInt64 in [100, 300] {
      let decision = Reconciler.decide(
        local: local(version: 5, synced: 3, deleted: true, wall: 200),
        remote: remote(version: 4, deleted: true, wall: wall), payloads: payloads("a", "b"))
      #expect(decision == .takeRemote(copyLocal: false))
    }
  }

  // MARK: - Descent (Phase 10)

  private func history(_ versions: UInt64...) -> [RevisionEntry] {
    versions.reversed().map {
      RevisionEntry(version: $0, at: Date(timeIntervalSince1970: Double($0)), changed: ["notes"])
    }
  }

  @Test func aRemoteThatAlreadyHasTheLocalEditWinsWithNoCopy() {
    var mine = AccountPayload(title: "X", notes: "v2")
    mine.revisionHistory = history(1, 2)
    var theirs = AccountPayload(title: "X", notes: "v3")
    theirs.revisionHistory = history(1, 2, 3)
    // Even with the local stamp newer (a restored backup's row): the remote has seen it.
    #expect(
      Reconciler.decide(
        local: local(version: 2, synced: 1, wall: 300), remote: remote(version: 3, wall: 200),
        payloads: .init(local: mine, remote: theirs)) == .takeRemote(copyLocal: false))
    // And the other way round: a local edit made on top of the remote version.
    #expect(
      Reconciler.decide(
        local: local(version: 3, synced: 1, wall: 100), remote: remote(version: 2, wall: 200),
        payloads: .init(local: theirs, remote: mine)) == .keepLocal(copyRemote: false))
  }

  @Test func rivalEditsFromTheSameBaseAreNotDescent() {
    var mine = AccountPayload(title: "X", notes: "mine")
    mine.revisionHistory = history(1, 2)
    var theirs = AccountPayload(title: "X", notes: "theirs")
    theirs.revisionHistory = history(1)
    theirs.revisionHistory.insert(
      RevisionEntry(version: 2, at: Date(timeIntervalSince1970: 99), changed: ["notes"]), at: 0)
    #expect(!Reconciler.descends(theirs, from: mine))
    #expect(!Reconciler.descends(mine, from: theirs))
    #expect(!Reconciler.descends(mine, from: mine), "the same point is not later")
    #expect(!Reconciler.descends(mine, from: AccountPayload(title: "no history")))
  }

  @Test func aConflictWithoutPayloadsResolvesByClockAndKeepsACopy() {
    // Same content, but undecrypted: no 5a shortcut, so the safe outcome -- a copy.
    #expect(
      Reconciler.decide(
        local: local(version: 4, synced: 3, wall: 100), remote: remote(version: 4, wall: 200))
        == .takeRemote(copyLocal: true))
  }

  @Test func theSameContentLiveAgainstATombstoneIsStillAConflict() {
    // 5a needs the same deletion state: a delete is an edit too.
    let decision = Reconciler.decide(
      local: local(version: 4, synced: 3, wall: 100),
      remote: remote(version: 4, deleted: true, wall: 200), payloads: payloads("same", "same"))
    #expect(decision == .takeRemote(copyLocal: true))
  }
}
