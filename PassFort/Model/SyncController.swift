import AppKit
import Foundation
import Network
import Observation
import PassFortVault

/// The app's side of sync (`m5-sync.md` A.11): one per unlocked vault, owned by `AppModel`,
/// created on unlock and stopped on lock. It decides *when* the engine runs -- after unlock, 2 s
/// after a local write, every minute while PassFort is the active app, when the network comes
/// back, on request -- and publishes what the views show. The engine decides everything else.
///
/// Runs are single-flight: a trigger during a run asks for one more round when it ends. A hard
/// problem (`SyncError.pausesSync`) stops the automatic triggers until the user acts; a server
/// error or a `429` holds them off for a while (30 s doubling to 10 min, or `Retry-After`).
@MainActor @Observable
final class SyncController {
  /// Builds the client for an endpoint; throws the `SyncError` that refuses it (plain HTTP off
  /// loopback, no pins). `SyncTransport.api` in the app, an in-memory server in tests.
  typealias MakeAPI = @Sendable (URL) throws -> any SyncAPI

  /// What the engine last published, or `.off`.
  private(set) var status: SyncStatus = .off
  /// Where this vault syncs and how far it has got; `nil` while sync is off.
  private(set) var state: VaultRepository.SyncState?
  /// The last device list fetched with `refreshDevices`.
  private(set) var devices: [DeviceInfoDTO] = []
  /// True after a hard problem: only `syncNow` runs again.
  private(set) var isPaused = false
  /// The hard problem that paused sync, until the user has seen it (`SyncProblemSheet`).
  private(set) var problemToShow: SyncError?

  /// This Mac, as the server sees it.
  let device: DeviceDTO

  /// Released by `stop`, so the vault closes on the main actor at a known point -- not later,
  /// on whichever task happens to drop it last, while the next unlock opens the file.
  private var repository: VaultRepository?
  private let makeAPI: MakeAPI
  /// Called after a run that may have changed the records, so the model can rebuild its index.
  private let didRun: @MainActor (_ pulled: Bool) async -> Void

  private var engine: SyncEngine?
  private var runTask: Task<Void, Never>?
  private var runAgain = false
  private var debounceTask: Task<Void, Never>?
  private var tickTask: Task<Void, Never>?
  private var statusTask: Task<Void, Never>?
  private var pathMonitor: NWPathMonitor?
  private var holdOffUntil: Date?
  private var backoff: TimeInterval = 0
  private var stopped = false
  /// Tasks `cancel` cancelled, for `stop` to wait out.
  private var finishing: [Task<Void, Never>] = []

  static let debounce: Duration = .seconds(2)
  static let tick: Duration = .seconds(60)
  static let backoffRange: ClosedRange<TimeInterval> = 30...600

  init(
    repository: VaultRepository, device: DeviceDTO, makeAPI: @escaping MakeAPI,
    didRun: @escaping @MainActor (_ pulled: Bool) async -> Void
  ) {
    self.repository = repository
    self.device = device
    self.makeAPI = makeAPI
    self.didRun = didRun
  }

  // MARK: - Lifecycle

  /// Read the sync state and, if sync is on, run once and start the triggers.
  func start() async {
    await refreshState()
    guard state != nil, !stopped else { return }
    status = .idle(lastSyncedAt: state?.lastSyncedAt)
    startTriggers()
    trigger(manual: true)
  }

  /// Cancel everything -- the run in flight included -- wait for every task to end, and let go
  /// of the vault. Lock ends in this: sync never runs while locked, and a cancelled run leaves
  /// the vault consistent (every ingest is one commit). Once it returns, nothing here holds the
  /// vault open.
  func stop() async {
    cancel()
    let tasks = finishing
    finishing = []
    for task in tasks { await task.value }
    repository = nil
  }

  /// The synchronous half of `stop`, for `AppModel.lock`: every trigger and the run in flight
  /// are cancelled now; `stop` then waits for them.
  func cancel() {
    stopped = true
    finishing += [runTask, statusTask, debounceTask, tickTask].compactMap { $0 }
    cancelTasks()
  }

  private func cancelTasks() {
    runTask?.cancel()
    runTask = nil
    debounceTask?.cancel()
    debounceTask = nil
    tickTask?.cancel()
    tickTask = nil
    statusTask?.cancel()
    statusTask = nil
    pathMonitor?.cancel()
    pathMonitor = nil
    engine = nil
  }

  // MARK: - Triggers

  /// A local write happened: sync 2 s after the last one.
  func localChange() {
    guard state != nil, !stopped else { return }
    debounceTask?.cancel()
    debounceTask = Task { [weak self] in
      try? await Task.sleep(for: Self.debounce)
      guard !Task.isCancelled else { return }
      self?.trigger(manual: false)
    }
  }

  /// Sync now, from the user: clears a pause or a hold-off, and returns when the run (and any
  /// round it was asked for meanwhile) has finished.
  func syncNow() async {
    isPaused = false
    problemToShow = nil
    holdOffUntil = nil
    trigger(manual: true)
    await runTask?.value
  }

  private func trigger(manual: Bool) {
    guard !stopped, state != nil else { return }
    if !manual {
      if isPaused { return }
      if let holdOffUntil, holdOffUntil > Date() { return }
    }
    if runTask != nil {
      runAgain = true
      return
    }
    runTask = Task { [weak self] in
      await self?.runRounds()
    }
  }

  private func runRounds() async {
    repeat {
      runAgain = false
      await runOnce()
    } while runAgain && !Task.isCancelled && !stopped
    runTask = nil
  }

  private func startTriggers() {
    tickTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.tick)
        guard !Task.isCancelled else { return }
        if NSApplication.shared.isActive { self?.trigger(manual: false) }
      }
    }

    let networkReturned: @MainActor @Sendable () -> Void = { [weak self] in
      guard let self, self.status == .offline else { return }
      self.trigger(manual: false)
    }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
      guard path.status == .satisfied else { return }
      Task { await networkReturned() }
    }
    monitor.start(queue: .global(qos: .utility))
    pathMonitor = monitor
  }

  // MARK: - Running

  private func runOnce() async {
    let engine: SyncEngine
    do {
      engine = try currentEngine()
    } catch let error as SyncError {
      status = .problem(error)
      pause(error)
      return
    } catch {
      return
    }

    var pulled = true  // after a failure, pages may have landed before it
    do {
      let report = try await engine.run()
      pulled = report.pulled > 0
      backoff = 0
      holdOffUntil = nil
    } catch let error as SyncError {
      settle(after: error)
    } catch {
      // Cancelled (the vault is locking), or a storage error the engine already published.
    }
    guard !stopped else { return }
    await refreshState()
    await didRun(pulled)
  }

  /// What a failed run means for the next automatic one.
  private func settle(after error: SyncError) {
    switch error {
    case .rateLimited(let retryAfter):
      holdOffUntil = Date().addingTimeInterval(retryAfter)
    case .server(_, let retryAfter):
      backoff = min(max(backoff * 2, Self.backoffRange.lowerBound), Self.backoffRange.upperBound)
      holdOffUntil = Date().addingTimeInterval(max(backoff, retryAfter ?? 0))
    default:
      if error.pausesSync { pause(error) }
    }
  }

  private func pause(_ error: SyncError) {
    isPaused = true
    problemToShow = error
  }

  /// The problem sheet was closed; sync stays paused until Sync Now.
  func dismissProblem() {
    problemToShow = nil
  }

  /// The engine for the configured endpoint, made on first use; its status stream feeds `status`.
  private func currentEngine() throws -> SyncEngine {
    if let engine { return engine }
    guard let state, let repository else { throw SyncError.notEnabled }
    let engine = SyncEngine(
      api: try makeAPI(state.endpoint), repository: repository, device: device)
    adopt(engine)
    return engine
  }

  private func adopt(_ engine: SyncEngine) {
    self.engine = engine
    statusTask?.cancel()
    statusTask = Task { [weak self] in
      for await status in engine.statusUpdates {
        guard let self, !Task.isCancelled else { return }
        self.status = status
      }
    }
  }

  private func refreshState() async {
    state = try? await repository?.syncState()
    if state == nil { status = .off }
  }

  // MARK: - Turning it on and off

  /// Put this vault on the server at `endpoint` (A.11 `enable`) and upload everything.
  ///
  /// - Returns: the vault id other devices join with.
  /// - Throws: the `SyncError` that refused it -- an insecure endpoint, a wrong enrollment
  ///   secret, offline -- with nothing changed locally.
  @discardableResult
  func enable(endpoint: URL, enrollSecret: String) async throws -> UUID {
    guard state == nil else { throw SyncError.vaultExists }
    guard let repository else { throw SyncError.notEnabled }
    stopped = false
    let engine = SyncEngine(
      api: try makeAPI(endpoint), repository: repository, device: device)
    let vaultID = try await engine.enable(endpoint: endpoint, enrollSecret: enrollSecret)
    adopt(engine)
    await refreshState()
    isPaused = false
    status = .idle(lastSyncedAt: nil)
    startTriggers()
    trigger(manual: true)
    return vaultID
  }

  /// Turn sync off on this Mac, first deleting the server copy if asked. The records stay.
  ///
  /// - Throws: the `SyncError` of the delete; sync then stays on.
  func disable(deleteServerCopy: Bool) async throws {
    let running = runTask
    runTask?.cancel()
    await running?.value
    if deleteServerCopy { try await currentEngine().deleteServerCopy() }
    try await repository?.disableSync()
    cancelTasks()
    stopped = false
    isPaused = false
    problemToShow = nil
    devices = []
    await refreshState()
  }

  // MARK: - Devices

  func refreshDevices() async throws {
    devices = try await currentEngine().devices()
      .sorted { $0.lastSeenAt > $1.lastSeenAt }
  }

  /// Remove a device from the server; if it syncs again it starts over with a full resync.
  func removeDevice(_ id: UUID) async throws {
    try await currentEngine().removeDevice(id)
    devices.removeAll { $0.id == id }
  }
}

// MARK: - The transport

/// The app's sync client: `HTTPSyncAPI` checked against the CA pins bundled in `SyncPins.txt`.
nonisolated enum SyncTransport {
  /// Read once. A missing or malformed file means no pins, so every `https` endpoint is refused
  /// (`SyncError.noPins`) rather than trusted unpinned.
  static let pins: PinSet = {
    guard let url = Bundle.main.url(forResource: "SyncPins", withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return .none }
    let lines = text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    return (try? PinSet(base64: lines)) ?? .none
  }()

  static let api: SyncController.MakeAPI = { endpoint in
    try HTTPSyncAPI(endpoint: endpoint, pins: pins)
  }
}

// MARK: - Problems

extension SyncError {
  /// A problem the next automatic run won't fix: sync pauses until the user acts (A.11).
  var pausesSync: Bool {
    switch self {
    case .unauthorized, .forbidden, .notFound, .serverRollback, .tamperedRecord, .pinningFailed,
      .insecureEndpoint, .noPins, .redirectRefused, .invalidResponse, .badRequest, .tooLarge:
      true
    case .offline, .rateLimited, .server, .conflicts, .resyncRequired, .vaultExists,
      .headerConflict, .headerChangedElsewhere, .notEnabled:
      false
    }
  }

  /// One plain sentence for the footer, a sheet or an alert. Never carries a body or a key.
  var message: String {
    switch self {
    case .insecureEndpoint:
      "PassFort only syncs over https. Plain http is allowed for localhost only."
    case .noPins:
      "This copy of PassFort has no certificate pins, so it can't check the server."
    case .offline: "The sync server can't be reached."
    case .pinningFailed:
      "The server's certificate doesn't match the pins this copy of PassFort trusts. Sync is "
        + "paused. Update PassFort; never bypass the check."
    case .redirectRefused: "The server answered with a redirect, which PassFort refuses."
    case .invalidResponse: "The server's answer doesn't match what PassFort expects."
    case .badRequest: "The server refused a request as malformed."
    case .unauthorized:
      "The server doesn't accept this vault's key. It may have been recreated. Turn sync off and "
        + "on again."
    case .forbidden: "That enrollment secret is wrong."
    case .notFound: "The server has no such vault. Check the vault id, or whether it was deleted."
    case .vaultExists: "This vault already syncs."
    case .conflicts: "Other devices kept changing the same accounts. PassFort will try again."
    case .headerConflict, .headerChangedElsewhere:
      "The master password or recovery key was changed on another device. Unlock with the new "
        + "password to finish updating this Mac."
    case .resyncRequired: "The server needs a full resync. PassFort will do one."
    case .tooLarge: "An account is too large to sync. Shorten its notes or history."
    case .rateLimited(let after):
      "The server asked PassFort to wait \(Int(after.rounded(.up))) seconds."
    case .server(let status, _): "The sync server had an error (\(status)). PassFort will retry."
    case .notEnabled: "Sync is off for this vault."
    case .serverRollback:
      "The server has less than this Mac already received: it was rolled back or replaced. Sync "
        + "is paused, and nothing was changed here."
    case .tamperedRecord:
      "An account from the server failed its integrity check, so nothing from that batch was "
        + "applied. If this happens again, treat the server as compromised."
    }
  }
}
