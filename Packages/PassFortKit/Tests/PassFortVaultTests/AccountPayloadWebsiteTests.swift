import Foundation
import Testing

@testable import PassFortVault

@Suite struct AccountPayloadWebsiteTests {

  private func website(_ strings: String...) -> URL? {
    AccountPayload(title: "x", urls: strings.compactMap(URL.init(string:))).website
  }

  @Test func onlyWebAddressesWithAHostAreOpened() {
    #expect(
      website("file:///etc/passwd", "javascript:alert(1)", "ftp://h/x", "slack://open") == nil)
    #expect(website("https:///nohost") == nil)
    #expect(website() == nil)
  }

  @Test func theFirstWebAddressWinsWhateverItsCase() {
    #expect(
      website("mailto:me@x.com", "HTTP://Example.com/a", "https://b.com")?.host() == "Example.com")
  }
}
