import Foundation
import Testing

@testable import PassFortVault

/// `PlatformPaths` (`m6-portable-cli.md` Phase 3): the Application Support lookup, which Linux
/// answers with the XDG data home.
@Suite struct PlatformPathsTests {

  @Test func applicationSupportIsThePlatformsOwn() {
    #if canImport(Darwin)
      #expect(PlatformPaths.applicationSupport == URL.applicationSupportDirectory)
    #else
      let home = FileManager.default.homeDirectoryForCurrentUser
      let expected =
        ProcessInfo.processInfo.environment["XDG_DATA_HOME"].map { URL(filePath: $0) }
        ?? home.appending(path: ".local/share")
      #expect(
        PlatformPaths.applicationSupport.standardizedFileURL.path(percentEncoded: false)
          == expected.standardizedFileURL.path(percentEncoded: false))
    #endif
  }

  @Test func theDefaultVaultAndDeviceSitTogetherUnderIt() {
    let base = PlatformPaths.applicationSupport.appending(path: "PassFort")
    #expect(
      VaultDatabase.defaultPath
        == base.appending(path: "vault.sqlite").path(percentEncoded: false))
    #expect(DeviceIdentity.defaultURL == base.appending(path: "device.json"))
  }
}
