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
      // The XDG spec's terms: $XDG_DATA_HOME, else $HOME/.local/share. $HOME, not the passwd
      // entry: in CI's container they differ (/github/home vs /root), and Foundation reads $HOME.
      let environment = ProcessInfo.processInfo.environment
      let expected =
        environment["XDG_DATA_HOME"] ?? ((environment["HOME"] ?? "") + "/.local/share")
      func normalized(_ path: String) -> String {
        URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
          .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      }
      #expect(
        normalized(PlatformPaths.applicationSupport.path(percentEncoded: false))
          == normalized(expected))
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
