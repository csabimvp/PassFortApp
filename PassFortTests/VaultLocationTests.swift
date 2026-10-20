import Foundation
import Testing

@testable import PassFort

/// Which folders may hold the live vault, and how the app resolves its location at launch.
struct VaultLocationTests {

  private final class MemoryStore: VaultLocationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var record: VaultLocationRecord?
    private(set) var saves = 0
    func load() -> VaultLocationRecord? { lock.withLock { record } }
    func save(_ record: VaultLocationRecord?) {
      lock.withLock {
        self.record = record
        saves += 1
      }
    }
  }

  private func makeFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "pf-loc-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  // MARK: - Which folders are allowed

  @Test func anOrdinaryLocalFolderIsAllowed() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(SystemFolderChecker().problem(with: folder) == nil)
  }

  @Test func aMissingFolderAndAPlainFileAreNotFolders() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "f.txt")
    try Data("x".utf8).write(to: file)

    #expect(SystemFolderChecker().problem(with: folder.appending(path: "nope")) == .notAFolder)
    #expect(SystemFolderChecker().problem(with: file) == .notAFolder)
  }

  @Test func aReadOnlyFolderIsRefused() throws {
    let folder = try makeFolder()
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path())
      try? FileManager.default.removeItem(at: folder)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path())

    #expect(SystemFolderChecker().problem(with: folder) == .notWritable)
  }

  @Test(arguments: [
    "/Users/me/Library/CloudStorage/Dropbox/vaults",
    "/Users/me/Library/CloudStorage/OneDrive-Personal/x",
    "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Docs",
    "/Users/me/LIBRARY/CLOUDSTORAGE/GoogleDrive-me/x",
  ])
  func syncedFoldersAreRecognised(path: String) {
    #expect(SystemFolderChecker.isCloudSynced(path: path))
  }

  @Test(arguments: [
    "/Users/me/Documents/PassFort",
    "/Volumes/External/PassFort",
    "/Users/me/Library/Application Support/PassFort",
    "/Users/me/CloudStorageNotes",
  ])
  func ordinaryFoldersAreNotMistakenForSynced(path: String) {
    #expect(!SystemFolderChecker.isCloudSynced(path: path))
  }

  @Test func everyProblemHasAPlainSentence() {
    for problem in [LocationProblem.notAFolder, .notWritable, .networkVolume, .cloudSynced] {
      #expect(problem.message.hasSuffix("."))
    }
    #expect(LocationProblem.networkVolume.message.contains("backups"))
  }

  // MARK: - Paths

  @Test func theVaultSitsInAPassFortSubfolderOfTheChosenFolder() {
    let folder = URL(fileURLWithPath: "/Volumes/External/Stuff")
    #expect(
      VaultLocation.databasePath(inChosenFolder: folder) == "/Volumes/External/Stuff/PassFort/vault.sqlite")
  }

  @Test func theMarkLivesInTheAppsOwnStorageNotBesideTheVault() {
    let support = URL(fileURLWithPath: "/tmp/support")
    let mark = VaultLocation.customHighWaterURL(supportDirectory: support)
    #expect(mark.path(percentEncoded: false) == "/tmp/support/PassFort/location.hw")
  }

  // MARK: - Launch resolution

  @Test func noRecordMeansTheStandardLocation() {
    #expect(VaultLocation.resolveAtLaunch(store: MemoryStore()) == .standard)
  }

  @Test func aSavedFolderResolvesToACustomLocation() throws {
    let folder = try makeFolder()
    let support = try makeFolder()
    defer {
      try? FileManager.default.removeItem(at: folder)
      try? FileManager.default.removeItem(at: support)
    }
    let store = MemoryStore()
    store.save(
      VaultLocationRecord(
        bookmark: try FolderDestination.makeBookmark(for: folder),
        path: folder.path(percentEncoded: false)))

    let resolution = VaultLocation.resolveAtLaunch(store: store, supportDirectory: support)

    guard case .custom(let custom) = resolution else {
      Issue.record("expected .custom, got \(resolution)")
      return
    }
    #expect(custom.databasePath.hasSuffix("/PassFort/vault.sqlite"))
    #expect(custom.databasePath.contains(folder.lastPathComponent))
    // The mark's folder is ready for the first write.
    var isDirectory: ObjCBool = false
    let markFolder = VaultLocation.customHighWaterURL(supportDirectory: support)
      .deletingLastPathComponent().path(percentEncoded: false)
    #expect(FileManager.default.fileExists(atPath: markFolder, isDirectory: &isDirectory) && isDirectory.boolValue)
  }

  @Test func aFolderThatWentAwayIsUnavailableNeverNoVault() throws {
    let folder = try makeFolder()
    let store = MemoryStore()
    store.save(
      VaultLocationRecord(
        bookmark: try FolderDestination.makeBookmark(for: folder),
        path: folder.path(percentEncoded: false)))
    try FileManager.default.removeItem(at: folder)  // the drive was unplugged

    let resolution = VaultLocation.resolveAtLaunch(store: store)

    guard case .unavailable(let path, let reason) = resolution else {
      Issue.record("expected .unavailable, got \(resolution)")
      return
    }
    #expect(path.hasSuffix("/PassFort/vault.sqlite"))
    #expect(!reason.isEmpty)
  }

  @Test func anUnreadableBookmarkIsUnavailableToo() {
    let store = MemoryStore()
    store.save(VaultLocationRecord(bookmark: Data("garbage".utf8), path: "/Volumes/Gone"))

    guard case .unavailable(_, let reason) = VaultLocation.resolveAtLaunch(store: store) else {
      Issue.record("expected .unavailable")
      return
    }
    #expect(reason.contains("/Volumes/Gone"))
  }

  @Test func theUserDefaultsStoreRoundTripsAndClears() throws {
    let suite = "pf-loc-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsVaultLocationStore(defaults: defaults)
    let record = VaultLocationRecord(bookmark: Data([1, 2, 3]), path: "/Volumes/X")

    store.save(record)
    #expect(store.load() == record)
    store.save(nil)
    #expect(store.load() == nil)
  }
}
