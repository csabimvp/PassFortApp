import Foundation

/// Locks the vault after a period of inactivity.
///
/// **Phase 2:** a bare countdown, started when the vault unlocks and cancelled on
/// `lock()`. **Phase 8** adds `bump()` on user activity (an `NSEvent` monitor) and
/// a Settings-configurable interval. **M4** adds lock on sleep / screen-lock.
@MainActor
final class AutoLock {
  private var countdown: Task<Void, Never>?

  init(timeout: Duration = .seconds(300), onExpire: @escaping @MainActor () -> Void) {
    countdown = Task {
      try? await Task.sleep(for: timeout)
      guard !Task.isCancelled else { return }
      onExpire()
    }
  }

  /// Stop the countdown. `AppModel` calls this before dropping the instance so a
  /// stale timer can't fire against a locked vault.
  func invalidate() {
    countdown?.cancel()
    countdown = nil
  }
}
