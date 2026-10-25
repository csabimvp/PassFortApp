import Foundation
import Testing

@testable import PassFort

/// Reading a typed or pasted sync server address.
struct SyncEndpointTests {
  @Test func anApiRootIsTrimmedOfSpaceAndTrailingSlashes() {
    #expect(
      SyncEndpoint.parse("  https://site.azurestaticapps.net/api/v1// \n")
        == URL(string: "https://site.azurestaticapps.net/api/v1"))
    #expect(
      SyncEndpoint.parse("http://localhost:7071/api/v1") == URL(string: "http://localhost:7071/api/v1"))
  }

  @Test(arguments: ["", "site.azurestaticapps.net/api/v1", "ftp://host/api", "https://", "not a url"])
  func anythingElseIsRefused(text: String) {
    #expect(SyncEndpoint.parse(text) == nil)
  }
}
