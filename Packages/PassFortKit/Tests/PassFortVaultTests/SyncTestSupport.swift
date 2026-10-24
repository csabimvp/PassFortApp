import Foundation
import GRDB
import PassFortCrypto

@testable import PassFortVault

// The two-device harness the sync suites share (`m5-sync.md` Phases 8-10): vault files in a
// temporary directory, one `FakeSyncServer`, one hand-moved clock.

/// A wall clock a test moves by hand, shared by every device in it -- so "B edited later" is a
/// fact of the test, not of the machine's timing.
final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: UInt64 = 1_800_000_000_000

  var now: UInt64 { lock.withLock { value } }
  func advance(_ millis: UInt64 = 1_000) { lock.withLock { value += millis } }
  var wallClock: WallClock { WallClock { self.now } }
}

/// Set once, read many: a hook's "only the first time".
final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var fired = false

  /// True the first time only.
  func claim() -> Bool {
    lock.withLock {
      defer { fired = true }
      return !fired
    }
  }
}

/// A thread-safe counter for request hooks.
final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  /// The count after this call.
  func increment() -> Int {
    lock.withLock {
      value += 1
      return value
    }
  }
}

/// One device: its vault file, the repository and engine on it.
struct SyncDevice {
  let id: UUID
  let path: String
  let repo: VaultRepository
  let engine: SyncEngine
}

struct SyncWorld {
  static let endpoint = URL(string: "http://localhost:7071/api/v1")!
  static var fastParams: KdfParameters {
    KdfParameters(
      kdfID: 1, memoryKiB: 8 * 1024, iterations: 1, parallelism: 1, salt: Data(count: 16))
  }

  let server = FakeSyncServer()
  let clock = TestClock()
  let password = Data("correct horse".utf8)
  let dir: URL

  init() throws {
    dir = FileManager.default.temporaryDirectory.appending(path: "pf-sync-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  func cleanUp() { try? FileManager.default.removeItem(at: dir) }

  func path(_ name: String) -> String {
    dir.appending(path: "\(name).sqlite").path(percentEncoded: false)
  }

  /// A device with a fresh vault file built on `header`.
  func makeDevice(_ name: String, header: Data) async throws -> SyncDevice {
    let id = UUID()
    let path = path(name)
    let session = try VaultSession.open(header: header, password: password)
    let repo = try await VaultRepository.bootstrap(
      database: try VaultDatabase(path: path), session: session, header: header, deviceID: id,
      highWater: HighWaterMark(sidecarFor: path), wallClock: clock.wallClock)
    return SyncDevice(id: id, path: path, repo: repo, engine: engine(for: repo, id, name))
  }

  /// `device` after a lock and an unlock with `password` -- through `Vault.unlock`, so a pending
  /// header is adopted if the password opens it.
  func unlock(_ device: SyncDevice, password: Data) async throws -> SyncDevice {
    let repo = try await Vault.unlock(
      databasePath: device.path, password: password, deviceID: device.id)
    return SyncDevice(
      id: device.id, path: device.path, repo: repo,
      engine: engine(for: repo, device.id, "relocked"))
  }

  func engine(for repo: VaultRepository, _ id: UUID, _ name: String) -> SyncEngine {
    SyncEngine(api: server, repository: repo, device: DeviceDTO(id: id, name: name, platform: .cli))
  }

  /// Device A: a brand-new vault, put on the server.
  func enableA() async throws -> (device: SyncDevice, vaultID: UUID) {
    let header = try VaultSession.create(password: password, params: Self.fastParams)
    let a = try await makeDevice("A", header: header)
    let vaultID = try await a.engine.enable(endpoint: Self.endpoint, enrollSecret: "enroll")
    return (a, vaultID)
  }

  /// Another device joins (`Vault.join`): an empty vault built on the server's header.
  func join(_ name: String, _ vaultID: UUID) async throws -> SyncDevice {
    let id = UUID()
    let repo = try await Vault.join(
      databasePath: path(name), password: password, api: server, endpoint: Self.endpoint,
      vaultID: vaultID, deviceID: id, wallClock: clock.wallClock)
    return SyncDevice(id: id, path: path(name), repo: repo, engine: engine(for: repo, id, name))
  }

  /// Reopen from disk with the stored header: the manifest MAC and the anti-rollback mark must
  /// both verify. Does not adopt a pending header.
  func verify(_ device: SyncDevice, password: Data? = nil) async throws {
    let database = try VaultDatabase(path: device.path)
    let header = try await database.dbQueue.read { db in try VaultMeta.read(db, .header) }
    _ = try await VaultRepository.open(
      database: database,
      session: try VaultSession.open(header: header ?? Data(), password: password ?? self.password),
      deviceID: device.id, highWater: HighWaterMark(sidecarFor: device.path))
  }

  /// Every conflict copy of `id` on `device`.
  func copies(of id: UUID, on device: SyncDevice) async throws -> [Account] {
    try await device.repo.allAccounts().filter { $0.payload.conflictOf == id }
  }

  /// How many `call`s the server saw since `start` (an index into `server.calls`).
  func calls(from start: Int, _ call: FakeSyncServer.Call) async -> Int {
    await server.calls.dropFirst(start).filter { $0 == call }.count
  }
}
