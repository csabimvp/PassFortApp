import Testing

@testable import PassFort

/// The vault window's "… copied" toast: what it says, and that it goes away on its own.
@MainActor
struct ToastCenterTests {

  @Test func aSecretSaysWhenItClears() {
    let message = ToastCenter.message(copying: "Password", .secret)
    #expect(message == "Password copied — clears in \(Pasteboard.clearAfterDescription)")
  }

  @Test func otherCopiesJustSaySo() {
    #expect(ToastCenter.message(copying: "Username", .value) == "Username copied")
    #expect(ToastCenter.message(copying: "invite link", .plain) == "Invite link copied")
  }

  /// Waits for `condition` up to `limit`: under a busy test run the clearing task can start late,
  /// so "goes away" is checked against a generous deadline, never a fixed sleep.
  private func eventually(
    within limit: Duration = .seconds(3), _ condition: () -> Bool
  ) async throws -> Bool {
    let deadline = ContinuousClock.now + limit
    while ContinuousClock.now < deadline {
      if condition() { return true }
      try await Task.sleep(for: .milliseconds(20))
    }
    return condition()
  }

  @Test func theMessageClearsAfterAMoment() async throws {
    let notice = ToastCenter(duration: .milliseconds(50))
    notice.show("Password copied")
    #expect(notice.message == "Password copied")

    #expect(try await eventually { notice.message == nil })
  }

  @Test func aNewerCopyReplacesTheMessageAndRestartsTheClock() async throws {
    let notice = ToastCenter(duration: .milliseconds(200))
    notice.show("Username copied")
    try await Task.sleep(for: .milliseconds(120))
    notice.show("Password copied")
    try await Task.sleep(for: .milliseconds(120))

    #expect(notice.message == "Password copied", "the first copy's timer must not clear the second")
    #expect(try await eventually { notice.message == nil })
  }

  @Test func aToastWithUndoStaysLongerAndRunsItOnce() async throws {
    let toasts = ToastCenter(duration: .milliseconds(50), actionDuration: .milliseconds(400))
    var undone = 0
    toasts.showDeleted("GitHub") { undone += 1 }
    #expect(toasts.message == "“GitHub” moved to Recently Deleted")
    #expect(toasts.notice?.action?.title == "Undo")

    try await Task.sleep(for: .milliseconds(150))
    #expect(toasts.notice != nil, "long enough to reach for Undo")

    toasts.performAction()
    toasts.performAction()
    #expect(undone == 1)
    #expect(toasts.notice == nil)
  }
}
