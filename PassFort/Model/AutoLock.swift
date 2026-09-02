import AppKit

/// Locks the vault after a period of inactivity.
///
/// **M3:** an idle countdown restarted on key / mouse / scroll activity while the
/// app is frontmost, plus `PassFortApp`'s lock-on-`.background`. **M4** adds lock
/// on system sleep (`NSWorkspace.willSleepNotification`) and screen lock.
@MainActor
final class AutoLock {
  private var countdown: Task<Void, Never>?
  private var monitor: Any?
  private let timeout: Duration
  private let onExpire: @MainActor () -> Void

  init(timeout: Duration = .seconds(300), onExpire: @escaping @MainActor () -> Void) {
    self.timeout = timeout
    self.onExpire = onExpire
    monitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
    ) { [weak self] event in
      self?.bump()
      return event
    }
    bump()
    // TODO(M4): also lock on NSWorkspace.willSleepNotification / screen lock.
  }

  /// Restart the countdown — called on user activity.
  func bump() {
    countdown?.cancel()
    countdown = Task {
      try? await Task.sleep(for: timeout)
      guard !Task.isCancelled else { return }
      onExpire()
    }
  }

  /// Stop the countdown and drop the event monitor. `AppModel` calls this before
  /// dropping the instance so nothing fires against a locked vault.
  func invalidate() {
    countdown?.cancel()
    countdown = nil
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }
}
