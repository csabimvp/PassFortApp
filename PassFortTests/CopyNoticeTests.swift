import Testing

@testable import PassFort

/// The vault window's "… copied" toast: what it says, and that it goes away on its own.
@MainActor
struct CopyNoticeTests {

  @Test func aSecretSaysWhenItClears() {
    let message = CopyNotice.message(copying: "Password", .secret)
    #expect(message == "Password copied — clears in \(Pasteboard.clearAfterDescription)")
  }

  @Test func otherCopiesJustSaySo() {
    #expect(CopyNotice.message(copying: "Username", .value) == "Username copied")
    #expect(CopyNotice.message(copying: "invite link", .plain) == "Invite link copied")
  }

  @Test func theMessageClearsAfterAMoment() async throws {
    let notice = CopyNotice(duration: .milliseconds(50))
    notice.show("Password copied")
    #expect(notice.message == "Password copied")

    try await Task.sleep(for: .milliseconds(300))
    #expect(notice.message == nil)
  }

  @Test func aNewerCopyReplacesTheMessageAndRestartsTheClock() async throws {
    let notice = CopyNotice(duration: .milliseconds(200))
    notice.show("Username copied")
    try await Task.sleep(for: .milliseconds(120))
    notice.show("Password copied")
    try await Task.sleep(for: .milliseconds(120))

    #expect(notice.message == "Password copied", "the first copy's timer must not clear the second")
    try await Task.sleep(for: .milliseconds(300))
    #expect(notice.message == nil)
  }
}
