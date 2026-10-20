import Foundation
import PassFortVault
import Testing

@testable import PassFort

/// `FolderDestination` against real folders and real security-scoped bookmarks. "Unmounted" is
/// simulated by deleting the folder; a moved folder stands in for a remounted/renamed share.
struct FolderDestinationTests {

  /// In-memory `BookmarkStore`, so tests never touch `UserDefaults.standard`.
  private final class MemoryBookmarkStore: BookmarkStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private(set) var saveCount = 0

    func load() -> Data? { lock.withLock { data } }
    func save(_ bookmark: Data?) {
      lock.withLock {
        data = bookmark
        saveCount += 1
      }
    }
  }

  private struct Fixture {
    let root: URL
    let folder: URL
    let bookmarks: MemoryBookmarkStore
    let destination: FolderDestination

    func localFile(named name: String, contents: String = "sealed bytes") throws -> URL {
      let url = root.appending(path: name)
      try Data(contents.utf8).write(to: url)
      return url
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
  }

  private func makeFixture(configured: Bool = true) throws -> Fixture {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "pf-dest-\(UUID().uuidString)")
    let folder = root.appending(path: "backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let bookmarks = MemoryBookmarkStore()
    if configured { bookmarks.save(try FolderDestination.makeBookmark(for: folder)) }
    return Fixture(
      root: root, folder: folder, bookmarks: bookmarks,
      destination: FolderDestination(bookmarks: bookmarks))
  }

  private func names(in folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
  }

  // MARK: - store

  @Test func storesAFileIntactAndLeavesNoPartial() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    let vault = UUID()
    let name = VaultBackup.fileName(vaultID: vault, at: .now)
    let local = try f.localFile(named: name, contents: "snapshot-1")

    let stored = try await f.destination.store(local)

    #expect(stored == name)
    #expect(try names(in: f.folder) == [name])  // no ".<name>.partial" left behind
    #expect(try String(contentsOf: f.folder.appending(path: name), encoding: .utf8) == "snapshot-1")
  }

  @Test func neverOverwritesAnExistingBackup() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    let name = VaultBackup.fileName(vaultID: UUID(), at: .now)
    _ = try await f.destination.store(try f.localFile(named: name, contents: "first"))

    await #expect(throws: AppError.self) {
      _ = try await f.destination.store(try f.localFile(named: name, contents: "second"))
    }
    #expect(try String(contentsOf: f.folder.appending(path: name), encoding: .utf8) == "first")
  }

  @Test func aMissingSourceFailsCleanly() async throws {
    let f = try makeFixture()
    defer { f.remove() }

    await #expect(throws: AppError.self) {
      _ = try await f.destination.store(f.root.appending(path: "nope.sqlite"))
    }
    #expect(try names(in: f.folder).isEmpty)
  }

  @Test func aStalePartialFromACrashedCopyIsReplaced() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    let name = VaultBackup.fileName(vaultID: UUID(), at: .now)
    try Data("torn".utf8).write(to: f.folder.appending(path: ".\(name).partial"))

    _ = try await f.destination.store(try f.localFile(named: name))

    #expect(try names(in: f.folder) == [name])
  }

  // MARK: - availability

  @Test func notConfiguredIsItsOwnError() async throws {
    let f = try makeFixture(configured: false)
    defer { f.remove() }
    #expect(!f.destination.isConfigured)

    await #expect(throws: AppError.backupNotConfigured) {
      _ = try await f.destination.store(try f.localFile(named: "x.sqlite"))
    }
  }

  @Test func anUnmountedFolderReadsAsUnavailableAndIsNeverRecreated() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    try FileManager.default.removeItem(at: f.folder)  // the share went away

    await #expect {
      _ = try await f.destination.store(try f.localFile(named: "x.sqlite"))
    } throws: { error in
      if case AppError.backupDestinationUnavailable = error { return true }
      return false
    }
    #expect(!FileManager.default.fileExists(atPath: f.folder.path(percentEncoded: false)))
  }

  @Test func theBookmarkFollowsAMovedFolderAndIsRefreshed() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    let moved = f.root.appending(path: "renamed", directoryHint: .isDirectory)
    try FileManager.default.moveItem(at: f.folder, to: moved)
    let before = f.bookmarks.load()

    let name = VaultBackup.fileName(vaultID: UUID(), at: .now)
    _ = try await f.destination.store(try f.localFile(named: name))

    #expect(try names(in: moved) == [name])
    #expect(f.destination.displayName == "renamed")
    // A moved target makes the bookmark stale; the destination re-saves a fresh one.
    #expect(f.bookmarks.saveCount >= 2)
    #expect(f.bookmarks.load() != before)
  }

  // MARK: - list and prune

  @Test func listAndPruneOnlyTouchThisVaultsBackups() async throws {
    let f = try makeFixture()
    defer { f.remove() }
    let mine = UUID()
    let other = UUID()
    let stamps: [Double] = [1_700_000_000, 1_700_086_400, 1_700_172_800]
    var mineNames: [String] = []
    for t in stamps {
      let name = VaultBackup.fileName(vaultID: mine, at: Date(timeIntervalSince1970: t))
      mineNames.append(name)
      _ = try await f.destination.store(try f.localFile(named: name))
    }
    let otherName = VaultBackup.fileName(vaultID: other, at: Date(timeIntervalSince1970: 1_700_000_000))
    _ = try await f.destination.store(try f.localFile(named: otherName))

    #expect(try await f.destination.list(vaultID: mine) == mineNames.reversed())

    let removed = try await f.destination.prune(vaultID: mine, keep: 1)

    #expect(removed.count == 2)
    #expect(try await f.destination.list(vaultID: mine) == [mineNames[2]])
    #expect(try await f.destination.list(vaultID: other) == [otherName])
  }
}
