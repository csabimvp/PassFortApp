import Foundation
import Testing

@testable import PassFortVault

/// `HLCClock` (m5-sync.md A.5): stamps never go backwards, and `receive` moves the clock past
/// every stamp it has seen -- with the wall clock frozen, stepped and running backwards.
@Suite struct HLCClockTests {

  private let me = UUID(uuid: (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1))
  private let them = UUID(uuid: (2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2))

  /// A wall clock the test sets by hand.
  private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64
    init(_ millis: UInt64) { value = millis }
    var millis: UInt64 {
      get { lock.withLock { value } }
      set { lock.withLock { value = newValue } }
    }
    var wallClock: WallClock { WallClock { self.millis } }
  }

  private func stamp(_ wall: UInt64, _ counter: UInt32, _ device: UUID) -> HLC {
    HLC(wallMillis: wall, counter: counter, deviceID: device)
  }

  @Test func tickTakesTheWallTimeWhenItMovesAndCountsWhenItDoesNot() async {
    let time = ManualClock(1_000)
    let clock = HLCClock(deviceID: me, seed: nil, wallClock: time.wallClock)

    let first = await clock.tick()
    #expect(first == stamp(1_000, 0, me))
    #expect(await clock.tick() == stamp(1_000, 1, me))
    #expect(await clock.tick() == stamp(1_000, 2, me))
    time.millis = 1_005
    #expect(await clock.tick() == stamp(1_005, 0, me))
  }

  @Test func tickNeverGoesBackwardsWhenTheWallClockDoes() async {
    let time = ManualClock(5_000)
    let clock = HLCClock(deviceID: me, seed: nil, wallClock: time.wallClock)
    let before = await clock.tick()
    time.millis = 4_000  // NTP stepped the clock back
    let after = await clock.tick()
    #expect(after > before)
    #expect(after == stamp(5_000, 1, me))
  }

  @Test func aSeedContinuesFromTheVaultsNewestStamp() async {
    let time = ManualClock(1_000)
    // The vault already holds a stamp from the future (another machine's skewed clock).
    let clock = HLCClock(
      deviceID: me, seed: stamp(9_000, 4, them), wallClock: time.wallClock)
    #expect(await clock.tick() == stamp(9_000, 5, me))
  }

  @Test func receiveMovesPastARemoteStampAhead() async {
    let time = ManualClock(1_000)
    let clock = HLCClock(deviceID: me, seed: nil, wallClock: time.wallClock)
    _ = await clock.tick()  // (1000, 0)

    let remote = stamp(2_000, 7, them)
    #expect(await clock.receive(remote) == stamp(2_000, 8, me))
    let next = await clock.tick()
    #expect(next > remote, "a local edit after a pull outranks what it pulled")
  }

  @Test func receiveFollowsEveryBranchOfTheA5Rule() async {
    let time = ManualClock(1_000)
    let clock = HLCClock(deviceID: me, seed: stamp(1_000, 3, me), wallClock: time.wallClock)

    // wall == last == remote: max of both counters, plus one.
    #expect(await clock.receive(stamp(1_000, 9, them)) == stamp(1_000, 10, me))
    // wall == last only (the remote is behind): last's counter, plus one.
    #expect(await clock.receive(stamp(500, 99, them)) == stamp(1_000, 11, me))
    // wall == remote only (the remote is ahead): remote's counter, plus one.
    #expect(await clock.receive(stamp(1_500, 2, them)) == stamp(1_500, 3, me))
    // Now is ahead of both: counter resets.
    time.millis = 3_000
    #expect(await clock.receive(stamp(2_000, 50, them)) == stamp(3_000, 0, me))
  }

  @Test func aSaturatedCounterCarriesIntoTheWallTime() async {
    let time = ManualClock(1_000)
    let clock = HLCClock(
      deviceID: me, seed: stamp(1_000, .max, me), wallClock: time.wallClock)
    let next = await clock.tick()
    #expect(next == stamp(1_001, 0, me))
    #expect(next > stamp(1_000, .max, me))
  }
}
