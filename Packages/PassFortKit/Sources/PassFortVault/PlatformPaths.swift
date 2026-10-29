import Foundation

enum PlatformPaths {
  /// `~/Library/Application Support` on Apple platforms (inside the sandbox container for the app).
  /// swift-corelibs-foundation has no `URL.applicationSupportDirectory`; on Linux its `FileManager`
  /// lookup answers with the XDG data home (`$XDG_DATA_HOME`, else `~/.local/share`).
  static var applicationSupport: URL {
    #if canImport(Darwin)
      URL.applicationSupportDirectory
    #else
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/share")
    #endif
  }
}
