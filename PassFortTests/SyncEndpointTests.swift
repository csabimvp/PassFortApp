import CoreImage
import Foundation
import PassFortVault
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

  @Test(arguments: ["https://site.azurestaticapps.net", " https://site.azurestaticapps.net/ \n"])
  func aBareHostGainsTheApiRoot(text: String) {
    #expect(SyncEndpoint.parse(text) == URL(string: "https://site.azurestaticapps.net/api/v1"))
  }

  @Test func aWrongPathIsExplainedNotRetried() {
    let message = SyncError.server(status: 405, retryAfter: nil).message
    #expect(message.contains("/api/v1"))
    #expect(!message.contains("retry"))
  }

  @Test(arguments: ["", "site.azurestaticapps.net/api/v1", "ftp://host/api", "https://", "not a url"])
  func anythingElseIsRefused(text: String) {
    #expect(SyncEndpoint.parse(text) == nil)
  }
}

/// The join invite a QR code carries.
struct SyncInviteTests {
  @Test func anInviteRoundTripsThroughItsURL() throws {
    let invite = SyncInvite(
      endpoint: try #require(URL(string: "https://site.azurestaticapps.net/api/v1")),
      vaultID: UUID())
    #expect(invite.url.scheme == "passfort")
    #expect(SyncInvite.parse(invite.url.absoluteString) == invite)
    #expect(SyncInvite.parse("  \(invite.url.absoluteString)\n") == invite)
  }

  @Test(arguments: [
    "https://site.azurestaticapps.net/api/v1",
    "passfort://join?endpoint=https://site/api/v1",
    "passfort://join?vault=6f1c1f9e-2a7d-4e5b-9c3a-1b2c3d4e5f60",
    "passfort://join?endpoint=ftp://site&vault=6f1c1f9e-2a7d-4e5b-9c3a-1b2c3d4e5f60",
    "passfort://open?endpoint=https://site/api/v1&vault=6f1c1f9e-2a7d-4e5b-9c3a-1b2c3d4e5f60",
  ])
  func incompleteOrForeignLinksAreNotInvites(text: String) {
    #expect(SyncInvite.parse(text) == nil)
  }
}

/// The Add a Device QR code reads back as the invite it was made from.
struct InviteQRCodeTests {
  @Test func theQRCodeDecodesToTheInvite() throws {
    let invite = SyncInvite(
      endpoint: try #require(URL(string: "https://site.azurestaticapps.net/api/v1")),
      vaultID: UUID())
    let image = try #require(QRCodeImage.make(invite.url.absoluteString))
    let messages = QRCodeReader.messages(in: CIImage(cgImage: image))
    #expect(messages.compactMap(SyncInvite.parse) == [invite])
  }
}
