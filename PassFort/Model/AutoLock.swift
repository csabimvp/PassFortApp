import AppKit

/// Locks the vault after a period of inactivity.
///
/// An idle countdown restarted on key / mouse / scroll activity while the app is frontmost, plus
/// `PassFortApp`'s lock-on-`.background`, and an immediate lock when the Mac sleeps
/// (`NSWorkspace.willSleepNotification`) or the screen locks (`com.apple.screenIsLocked`, which is
/// undocumented but stable: if it ever stops arriving, sleep, idle and background still lock).
@MainActor
final class AutoLock {
  private var countdown: Task<Void, Never>?
  private var monitor: Any?
  private var systemObservers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
  private let timeout: Duration
  private let onExpire: @MainActor () -> Void

  /// The two notification centers are injectable so tests can post the system notifications
  /// themselves instead of sleeping the machine.
  init(
    timeout: Duration = .seconds(300),
    workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
    onExpire: @escaping @MainActor () -> Void
  ) {
    self.timeout = timeout
    self.onExpire = onExpire
    monitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
    ) { [weak self] event in
      self?.bump()
      return event
    }
    bump()
    observe(NSWorkspace.willSleepNotification, on: workspaceCenter)
    observe(Notification.Name("com.apple.screenIsLocked"), on: distributedCenter)
  }

  private func observe(_ name: Notification.Name, on center: NotificationCenter) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.onExpire() }
    }
    systemObservers.append((center, token))
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
    for (center, token) in systemObservers { center.removeObserver(token) }
    systemObservers = []
  }
}
