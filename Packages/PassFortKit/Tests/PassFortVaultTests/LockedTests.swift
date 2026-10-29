import Foundation
import Testing

@testable import PassFortVault

/// `Locked` (`m6-portable-cli.md` Phase 3): the `OSAllocatedUnfairLock` stand-in that also builds
/// on Linux.
@Suite struct LockedTests {

  @Test func concurrentUpdatesAreNeverLost() async {
    let counter = Locked(initialState: 0)
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<8 {
        group.addTask {
          for _ in 0..<1_000 { counter.withLock { $0 += 1 } }
        }
      }
    }
    #expect(counter.withLock { $0 } == 8_000)
  }

  @Test func returnsTheBodysResult() {
    let failures = Locked(initialState: Set([7]))
    #expect(failures.withLock { $0.remove(7) != nil })
    #expect(!failures.withLock { $0.remove(7) != nil }, "true once, as takePinFailure relies on")
  }

  @Test func rethrowsAndReleasesTheLock() {
    struct Boom: Error {}
    let value = Locked(initialState: 1)
    #expect(throws: Boom.self) { try value.withLock { _ in throw Boom() } }
    #expect(value.withLock { $0 } == 1, "the lock was released after the throw")
  }
}
