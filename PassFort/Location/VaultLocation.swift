import Foundation
import PassFortVault

/// Why a folder can't hold the live vault. Network drives and synced folders are refused outright:
/// SQLite's write-ahead log needs shared memory and reliable file locks, and a sync client
/// rewriting the files under an open database corrupts it. (Both remain fine *backup* destinations,
/// which only ever receive finished single files.)
nonisolated enum LocationProblem: Equatable, Sendable {
  case notAFolder
  case notWritable
  case networkVolume
  case cloudSynced

  var message: String {
    switch self {
    case .notAFolder:
      return "That isn't a folder."
    case .notWritable:
      return "PassFort can't write to that folder."
    case .networkVolume:
      return
        "That folder is on a network drive. A vault kept there can be corrupted by network "
        + "hiccups. Keep it on this Mac or an attached drive, and use the network drive for backups."
    case .cloudSynced:
      return
        "That folder is synced by iCloud, Dropbox or a similar service, which can corrupt a vault "
        + "that is open. Choose a folder that isn't synced."
    }
  }
}

/// A seam so tests can pretend a folder is on a network drive.
nonisolated protocol FolderChecking: Sendable {
  func problem(with folder: URL) -> LocationProblem?
}

nonisolated struct SystemFolderChecker: FolderChecking {
  /// File-provider and iCloud locations. Matching is on the symlink-resolved path.
  static func isCloudSynced(path: String) -> Bool {
    let lowered = path.lowercased()
    return ["/library/cloudstorage/", "/library/mobile documents/", "/com~apple~clouddocs"]
      .contains { lowered.contains($0) }
  }

  func problem(with folder: URL) -> LocationProblem? {
    let resolved = folder.resolvingSymlinksInPath()
    let path = resolved.path(percentEncoded: false)

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue
    else { return .notAFolder }
    guard FileManager.default.isWritableFile(atPath: path) else { return .notWritable }

    let values = try? resolved.resourceValues(forKeys: [.volumeIsLocalKey, .isUbiquitousItemKey])
    if values?.volumeIsLocal == false { return .networkVolume }
    if Self.isCloudSynced(path: path) || values?.isUbiquitousItem == true { return .cloudSynced }
    return nil
  }
}

/// What is remembered about a user-chosen vault folder: the bookmark that reopens it after a
/// relaunch, and its path for messages when the bookmark can no longer be resolved.
nonisolated struct VaultLocationRecord: Codable, Equatable, Sendable {
  let bookmark: Data
  let path: String
}

nonisolated protocol VaultLocationStore: Sendable {
  func load() -> VaultLocationRecord?
  func save(_ record: VaultLocationRecord?)
}

nonisolated struct UserDefaultsVaultLocationStore: VaultLocationStore {
  static let key = "vault.location"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func load() -> VaultLocationRecord? {
    defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(VaultLocationRecord.self, from: $0) }
  }

  func save(_ record: VaultLocationRecord?) {
    if let record, let data = try? JSONEncoder().encode(record) {
      defaults.set(data, forKey: Self.key)
    } else {
      defaults.removeObject(forKey: Self.key)
    }
  }
}

/// Where the live vault lives: the app's own storage (the default), or a folder the user chose.
nonisolated enum VaultLocation {
  static let folderName = "PassFort"
  static let fileName = "vault.sqlite"

  /// A vault in a chosen folder: its database path and the folder the user picked.
  struct Custom: Equatable, Sendable {
    let folder: URL
    let databasePath: String
  }

  enum Resolution: Equatable, Sendable {
    /// Application Support, as before. No bookmark is stored.
    case standard
    case custom(Custom)
    /// A folder was chosen but can't be reached now (an unplugged drive, a deleted folder). This is
    /// never treated as "no vault": the app must not offer to create a new one.
    case unavailable(path: String, reason: String)
  }

  /// `<chosen>/PassFort/vault.sqlite`. The subfolder keeps the database, its `-wal`/`-shm` and
  /// the Spotlight marker from cluttering whatever folder was picked (an external drive's root).
  static func databasePath(inChosenFolder folder: URL) -> String {
    folder.appending(path: folderName, directoryHint: .isDirectory)
      .appending(path: fileName).path(percentEncoded: false)
  }

  /// The anti-rollback mark for a vault in a chosen folder: in the app's own storage, never beside
  /// the vault. Beside it, a restored old copy of the folder would restore an old mark with it and
  /// defeat the check.
  static func customHighWaterURL(supportDirectory: URL = .applicationSupportDirectory) -> URL {
    supportDirectory.appending(path: folderName, directoryHint: .isDirectory)
      .appending(path: "location.hw")
  }

  /// Decide, once at launch, where the vault is. For a chosen folder this resolves the bookmark and
  /// **opens its security scope and deliberately never closes it**: the database's `-wal`/`-shm`
  /// files live in that folder for as long as the app runs.
  static func resolveAtLaunch(
    store: any VaultLocationStore = UserDefaultsVaultLocationStore(),
    supportDirectory: URL = .applicationSupportDirectory
  ) -> Resolution {
    guard let record = store.load() else { return .standard }
    let missing = databasePath(inChosenFolder: URL(fileURLWithPath: record.path))

    var stale = false
    guard
      let folder = try? URL(
        resolvingBookmarkData: record.bookmark, options: .withSecurityScope, relativeTo: nil,
        bookmarkDataIsStale: &stale)
    else {
      return .unavailable(path: missing, reason: "PassFort can't find “\(record.path)”.")
    }
    _ = folder.startAccessingSecurityScopedResource()

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      return .unavailable(
        path: missing, reason: "“\(folder.lastPathComponent)” isn't available. Is the drive connected?")
    }

    if stale, let fresh = try? FolderDestination.makeBookmark(for: folder) {
      store.save(VaultLocationRecord(bookmark: fresh, path: folder.path(percentEncoded: false)))
    }
    // The mark lives in the app's own storage; make sure its folder exists before the first write.
    try? FileManager.default.createDirectory(
      at: customHighWaterURL(supportDirectory: supportDirectory).deletingLastPathComponent(),
      withIntermediateDirectories: true)
    return .custom(Custom(folder: folder, databasePath: databasePath(inChosenFolder: folder)))
  }
}
