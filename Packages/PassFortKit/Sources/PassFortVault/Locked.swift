import Foundation

/// A value behind an `NSLock`, with `OSAllocatedUnfairLock`'s shape so call sites read the same.
/// `os` doesn't exist on Linux, and `Synchronization.Mutex` needs macOS 15 while the package
/// targets macOS 14 (`m6-portable-cli.md` 0.5).
final class Locked<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(initialState: Value) {
    value = initialState
  }

  /// Runs `body` with exclusive access to the value. Not reentrant: calling `withLock` on the same
  /// instance from inside `body` deadlocks.
  func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }
}
