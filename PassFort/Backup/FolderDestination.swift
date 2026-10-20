import Foundation
import PassFortVault

/// Where the app remembers the chosen folder. A seam so tests don't touch `UserDefaults.standard`.
nonisolated protocol BookmarkStore: Sendable {
  func load() -> Data?
  func save(_ bookmark: Data?)
}

/// The bookmark is a pointer to a folder, not a secret, so `UserDefaults` is the right home.
nonisolated struct UserDefaultsBookmarkStore: BookmarkStore {
  static let key = "backup.folderBookmark"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func load() -> Data? { defaults.data(forKey: Self.key) }

  func save(_ bookmark: Data?) {
    if let bookmark {
      defaults.set(bookmark, forKey: Self.key)
    } else {
      defaults.removeObject(forKey: Self.key)
    }
  }
}

/// A backup destination that is a user-chosen folder -- the NAS share.
///
/// The sandbox grants access to a folder only for the run in which the user picked it. To keep
/// writing after a relaunch, the app saves an app-scoped security bookmark (needs
/// `com.apple.security.files.bookmarks.app-scope`, see `PassFort.entitlements`; the Phase 0 spike
/// proved this against an SMB share). Every operation here resolves the bookmark, brackets its
/// I/O in `start/stopAccessingSecurityScopedResource`, and refreshes a stale bookmark in place.
///
/// It never creates the destination folder: if the share is unmounted, a missing path must read as
/// "unavailable", not be quietly recreated on the wrong volume.
nonisolated struct FolderDestination: BackupDestination {
  private let bookmarks: any BookmarkStore

  init(bookmarks: any BookmarkStore = UserDefaultsBookmarkStore()) {
    self.bookmarks = bookmarks
  }

  // MARK: - Choosing a folder

  /// The bookmark for a folder the user just picked in an open panel. Call while the panel's
  /// grant is still live, then `bookmarks.save` it.
  static func makeBookmark(for folder: URL) throws -> Data {
    try folder.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  var isConfigured: Bool { bookmarks.load() != nil }

  var displayName: String {
    guard let url = resolvedURL()?.url else { return "Backup folder" }
    return url.lastPathComponent
  }

  // MARK: - BackupDestination

  @concurrent func store(_ file: URL) async throws -> String {
    try withFolder { folder in
      let fm = FileManager.default
      let name = file.lastPathComponent
      let destination = folder.appending(path: name)
      let staging = folder.appending(path: ".\(name).partial")

      guard !fm.fileExists(atPath: destination.path(percentEncoded: false)) else {
        throw AppError.io("A backup named \(name) already exists in that folder.")
      }
      try? fm.removeItem(at: staging)  // left behind by an interrupted earlier copy
      do {
        try fm.copyItem(at: file, to: staging)
        try fm.moveItem(at: staging, to: destination)
      } catch {
        try? fm.removeItem(at: staging)
        throw error
      }

      // Read-back: a flaky share can accept a write and still hold the wrong bytes. Plain byte
      // comparison, deliberately not SQLite -- file locking over SMB/NFS is not reliable.
      guard fm.contentsEqual(atPath: file.path(percentEncoded: false),
        andPath: destination.path(percentEncoded: false))
      else {
        try? fm.removeItem(at: destination)
        throw AppError.io("The backup did not copy to the folder intact. Nothing was kept.")
      }
      return name
    }
  }

  @concurrent func list(vaultID: UUID) async throws -> [String] {
    try withFolder { folder in
      try VaultBackup.backups(in: folder, vaultID: vaultID).map(\.lastPathComponent)
    }
  }

  @concurrent func prune(vaultID: UUID, keep: Int) async throws -> [String] {
    try withFolder { folder in try VaultBackup.prune(in: folder, vaultID: vaultID, keep: keep) }
  }

  // MARK: - Bookmark access

  private func resolvedURL() -> (url: URL, stale: Bool)? {
    guard let data = bookmarks.load() else { return nil }
    var stale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
        bookmarkDataIsStale: &stale)
    else { return nil }
    return (url, stale)
  }

  /// Resolve, open the security scope, check the folder is really there, run `body`, close the
  /// scope. Errors from `body` that aren't already an `AppError` become `.io`.
  private func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
    guard bookmarks.load() != nil else { throw AppError.backupNotConfigured }
    guard let (url, stale) = resolvedURL() else {
      throw AppError.backupDestinationUnavailable("the backup folder")
    }

    // `false` is not fatal: it also means "no scope needed". Real permission problems surface as
    // file errors below.
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false),
      isDirectory: &isDirectory), isDirectory.boolValue
    else { throw AppError.backupDestinationUnavailable(url.lastPathComponent) }

    // The folder moved or the volume was remounted: the bookmark still found it, so save the
    // fresh one while the scope is open.
    if stale, let fresh = try? Self.makeBookmark(for: url) { bookmarks.save(fresh) }

    do {
      return try body(url)
    } catch let error as AppError {
      throw error
    } catch {
      throw AppError.io(error.localizedDescription)
    }
  }
}
