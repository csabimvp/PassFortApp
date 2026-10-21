import AppKit
import Testing

@testable import PassFort

/// The system-lock triggers, driven by posting the notifications on private centers.
@MainActor
struct AutoLockTests {

  private final class Counter {
    var count = 0
  }

  private func make(_ counter: Counter) -> (AutoLock, NotificationCenter, NotificationCenter) {
    let workspace = NotificationCenter()
    let distributed = NotificationCenter()
    let lock = AutoLock(
      timeout: .seconds(3600), workspaceCenter: workspace, distributedCenter: distributed
    ) { counter.count += 1 }
    return (lock, workspace, distributed)
  }

  @Test func sleepLocksImmediately() {
    let counter = Counter()
    let (lock, workspace, _) = make(counter)
    defer { lock.invalidate() }

    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    #expect(counter.count == 1)
  }

  @Test func screenLockLocksImmediately() {
    let counter = Counter()
    let (lock, _, distributed) = make(counter)
    defer { lock.invalidate() }

    distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
    #expect(counter.count == 1)
  }

  @Test func anInvalidatedAutoLockIgnoresSystemNotifications() {
    let counter = Counter()
    let (lock, workspace, distributed) = make(counter)
    lock.invalidate()

    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
    #expect(counter.count == 0)
  }
}
