import Foundation
import Observation
import PassFortVault

/// Where the live vault is, and moving it. The location is decided once at launch and does not
/// change while the app runs: a move finishes by asking for a relaunch. UI-free; tests drive it.
@MainActor @Observable
final class VaultLocationModel {
  struct Moved: Equatable {
    /// Where the vault will be at the next launch, for the message.
    let destination: String
    /// The old files, kept aside rather than deleted.
    let oldKeptAs: String?
    /// A different older file that was at the destination and was kept aside.
    let replacedKeptAs: String?
  }

  enum Step: Equatable {
    case idle
    case working
    case movedNeedsRelaunch(Moved)
    case failed(String)
  }

  /// What a move needs from the rest of the app (the same shape as `RestoreModel.Hooks`). There is
  /// no `reload`: a successful move ends in a relaunch, not a live swap.
  struct Hooks {
    /// Called first. Returns a reason to refuse (a backup is mid-run), or `nil` to go ahead.
    var begin: () -> String?
    /// Close the open vault so its files can move.
    var releaseVault: () -> Void
    /// Called when a move did *not* happen, so whatever `begin` paused can resume.
    var abandon: () -> Void
  }

  let resolution: VaultLocation.Resolution
  private(set) var step: Step = .idle

  private let store: any VaultLocationStore
  private let checker: any FolderChecking
  private let supportDirectory: URL
  private let defaultDatabasePath: String

  init(
    resolution: VaultLocation.Resolution,
    store: any VaultLocationStore = UserDefaultsVaultLocationStore(),
    checker: any FolderChecking = SystemFolderChecker(),
    supportDirectory: URL = .applicationSupportDirectory,
    defaultDatabasePath: String = VaultDatabase.defaultPath
  ) {
    self.resolution = resolution
    self.store = store
    self.checker = checker
    self.supportDirectory = supportDirectory
    self.defaultDatabasePath = defaultDatabasePath
  }

  /// Resolve the real location (opening a chosen folder's security scope for the whole session).
  static func launch() -> VaultLocationModel {
    VaultLocationModel(resolution: VaultLocation.resolveAtLaunch())
  }

  // MARK: - What the rest of the app builds on

  var databasePath: String {
    switch resolution {
    case .standard: return defaultDatabasePath
    case .custom(let custom): return custom.databasePath
    case .unavailable(let path, _): return path
    }
  }

  /// `nil` for the default location (the sidecar beside the vault).
  var highWaterURL: URL? {
    if case .standard = resolution { return nil }
    return VaultLocation.customHighWaterURL(supportDirectory: supportDirectory)
  }

  var isUsable: Bool {
    if case .unavailable = resolution { return false }
    return true
  }

  var isCustom: Bool {
    if case .standard = resolution { return false }
    return true
  }

  var unavailableReason: String? {
    if case .unavailable(_, let reason) = resolution { return reason }
    return nil
  }

  var isBusy: Bool { step == .working }

  var needsRelaunch: Bool {
    if case .movedNeedsRelaunch = step { return true }
    return false
  }

  /// The vault's path with the home directory abbreviated, for display.
  var displayPath: String { (databasePath as NSString).abbreviatingWithTildeInPath }

  // MARK: - Moving

  /// Move the vault into `folder` (the vault goes in `<folder>/PassFort/`). The folder must be a
  /// local, unsynced, writable one. Holds the folder's security scope for the duration.
  func move(to folder: URL, _ hooks: Hooks) async {
    guard !isBusy, !needsRelaunch else { return }
    if let problem = checker.problem(with: folder) {
      step = .failed(problem.message)
      return
    }
    let scoped = folder.startAccessingSecurityScopedResource()
    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

    let record: VaultLocationRecord
    do {
      record = VaultLocationRecord(
        bookmark: try FolderDestination.makeBookmark(for: folder),
        path: folder.path(percentEncoded: false))
    } catch {
      step = .failed("PassFort couldn't remember that folder: \(error.localizedDescription)")
      return
    }
    await perform(
      to: VaultMover.Endpoint(
        databasePath: VaultLocation.databasePath(inChosenFolder: folder),
        highWaterURL: VaultLocation.customHighWaterURL(supportDirectory: supportDirectory)),
      saving: record, hooks)
  }

  /// Move the vault back into the app's own storage.
  func useDefaultLocation(_ hooks: Hooks) async {
    guard !isBusy, !needsRelaunch, isCustom else { return }
    await perform(
      to: VaultMover.Endpoint(databasePath: defaultDatabasePath, highWaterURL: nil),
      saving: nil, hooks)
  }

  func dismiss() {
    if case .failed = step { step = .idle }
  }

  // MARK: - The move itself

  /// The endpoint the vault is at now; `nil` when it can't be read (an unplugged drive).
  private var currentEndpoint: VaultMover.Endpoint? {
    switch resolution {
    case .standard:
      return VaultMover.Endpoint(databasePath: defaultDatabasePath, highWaterURL: nil)
    case .custom(let custom):
      return VaultMover.Endpoint(
        databasePath: custom.databasePath,
        highWaterURL: VaultLocation.customHighWaterURL(supportDirectory: supportDirectory))
    case .unavailable:
      return nil
    }
  }

  /// Copy and verify, then switch the pointer, then retire the old files -- in that order, so a
  /// failure at any point before the switch leaves the old vault in place and still the one used.
  private func perform(
    to target: VaultMover.Endpoint, saving record: VaultLocationRecord?, _ hooks: Hooks
  ) async {
    if let reason = hooks.begin() {
      step = .failed(reason)
      return
    }
    step = .working
    hooks.releaseVault()
    await Task.yield()  // let the released vault's connection close before its files move

    let source = currentEndpoint
    do {
      let copied = try await VaultMover.copy(from: source, to: target)
      store.save(record)  // the switch
      let kept = copied.info == nil ? nil : source.flatMap { VaultMover.retire($0) }
      let destination =
        (target.databasePath as NSString).abbreviatingWithTildeInPath
      step = .movedNeedsRelaunch(
        Moved(destination: destination, oldKeptAs: kept, replacedKeptAs: copied.replacedAside))
      // Backups stay paused and the vault stays locked: this process still points at the old place.
    } catch {
      hooks.abandon()
      step = .failed((error as? AppError)?.message ?? AppError.io(error.localizedDescription).message)
    }
  }
}
