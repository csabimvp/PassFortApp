import Foundation

/// The wall clock an `HLCClock` reads, in Unix milliseconds. Injectable so a test can freeze or
/// step time; everything else uses `.system`.
public struct WallClock: Sendable {
  public let millis: @Sendable () -> UInt64

  public init(_ millis: @escaping @Sendable () -> UInt64) {
    self.millis = millis
  }

  public static let system = WallClock { UInt64(Date().timeIntervalSince1970 * 1000) }
}

/// The hybrid logical clock that stamps every write (`m5-sync.md` A.5, §9.3). Its stamps never go
/// backwards, even when the wall clock does or two writes land in the same millisecond, and after
/// `receive` they are ahead of every stamp seen from another device -- so "newer edit wins" (A.7)
/// means what it says across machines. Ordering is `HLC: Comparable` (wall, counter, device).
///
/// One per open repository, seeded with the newest stamp in the vault, so a reopened vault keeps
/// counting from where it was. An actor: the repository's writes and a sync run's ingest share it.
public actor HLCClock {
  private let deviceID: UUID
  private let wallClock: WallClock
  private var lastWall: UInt64
  private var lastCounter: UInt32

  /// - Parameter seed: the newest stamp already in the vault, or `nil` for an empty one. Its
  ///   device is irrelevant: the clock only continues its wall time and counter.
  public init(deviceID: UUID, seed: HLC?, wallClock: WallClock = .system) {
    self.deviceID = deviceID
    self.wallClock = wallClock
    lastWall = seed?.wallMillis ?? 0
    lastCounter = seed?.counter ?? 0
  }

  /// The stamp for a local write: `wall = max(now, last.wall)`, and the counter steps when the
  /// wall time didn't move.
  public func tick() -> HLC {
    let now = wallClock.millis()
    if now > lastWall {
      (lastWall, lastCounter) = (now, 0)
    } else {
      (lastWall, lastCounter) = Self.successor(lastWall, lastCounter)
    }
    return HLC(wallMillis: lastWall, counter: lastCounter, deviceID: deviceID)
  }

  /// Fold in a stamp from another device (every pulled record, A.6), so the next `tick` is
  /// ahead of it: `wall = max(now, last.wall, remote.wall)`, and the counter steps past
  /// whichever of the two stamps sits at that wall time.
  @discardableResult
  public func receive(_ remote: HLC) -> HLC {
    let wall = max(wallClock.millis(), lastWall, remote.wallMillis)
    let atLast = wall == lastWall
    let atRemote = wall == remote.wallMillis
    switch (atLast, atRemote) {
    case (true, true):
      (lastWall, lastCounter) = Self.successor(wall, max(lastCounter, remote.counter))
    case (true, false):
      (lastWall, lastCounter) = Self.successor(wall, lastCounter)
    case (false, true):
      (lastWall, lastCounter) = Self.successor(wall, remote.counter)
    case (false, false):
      (lastWall, lastCounter) = (wall, 0)
    }
    return HLC(wallMillis: lastWall, counter: lastCounter, deviceID: deviceID)
  }

  /// The next stamp after `(wall, counter)`. A counter at `UInt32.max` -- four billion writes in
  /// one millisecond -- carries into the wall time rather than wrapping back below its own past.
  private static func successor(_ wall: UInt64, _ counter: UInt32) -> (UInt64, UInt32) {
    counter < .max ? (wall, counter + 1) : (wall + 1, 0)
  }
}
