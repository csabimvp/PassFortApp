import Foundation
import PassFortCrypto
import PassFortVault

/// The one place the app calls into `PassFortKit`: the device id, the KDF target,
/// and the `PassFortError` → `AppError` translation in a single spot — the app's
/// `VaultCLI`.
///
/// `nonisolated` on purpose: the blocking Argon2id in `calibrate` and the async
/// `Vault.*` calls must run off the main actor, and every method here is pure
/// pass-through to `PassFortKit`.
nonisolated struct VaultService {
  /// This install's device (`m5-sync.md` A.5): `Application Support/PassFort/device.json` in
  /// the container, created on first launch and kept outside the vault file, so a copied or
  /// restored vault never clones it. It stamps every write's HLC and names this Mac to the sync
  /// server. `nil` if the file can't be read or written: local writes then stamp with a fresh id
  /// that isn't kept, which is harmless, and sync refuses to start -- a server would see a new
  /// device on every launch.
  static let storedDevice: DeviceIdentity? = try? DeviceIdentity.loadOrCreate(
    at: DeviceIdentity.defaultURL, name: DeviceIdentity.hostName)

  static let deviceID: UUID = storedDevice?.id ?? UUID()

  /// Sandboxed, so this resolves inside the app's container
  /// (`~/Library/Containers/…/Application Support/PassFort/vault.sqlite`), not the
  /// path the CLI uses. They converge in M5 (sync).
  let databasePath: String

  /// Where the anti-rollback mark lives. `nil` is the default, the `<db>.hw` sidecar beside the
  /// vault; a vault in a user-chosen folder keeps its mark in the app's own storage instead
  /// (`VaultLocation.customHighWaterURL`).
  let highWaterURL: URL?

  init(databasePath: String, highWaterURL: URL? = nil) {
    self.databasePath = databasePath
    self.highWaterURL = highWaterURL
  }

  private var highWater: HighWaterMark? { highWaterURL.map(HighWaterMark.init(url:)) }

  /// The mark this vault actually uses: the explicit one, or the sidecar beside the vault.
  private var highWaterMark: HighWaterMark { highWater ?? HighWaterMark(sidecarFor: databasePath) }

  /// Cheap, side-effect-free (§2.3): is there an initialised vault at the path?
  func exists() -> Bool { Vault.exists(databasePath: databasePath) }

  /// Measure Argon2id on this machine. Blocks ~500 ms — call inside
  /// `Task.detached` so the UI keeps animating.
  func calibrate(targetMs: UInt32 = 500) throws -> KdfParameters {
    try VaultSession.calibrate(targetMs: targetMs)
  }

  /// Create a vault; with `recovery`, also mint a recovery key (shown once).
  func createVault(
    password: Data, params: KdfParameters, recovery: Bool
  ) async throws -> (repo: VaultRepository, recoveryKey: RecoveryKey?) {
    do {
      if recovery {
        let (repo, key) = try await Vault.createWithRecovery(
          databasePath: databasePath, password: password, params: params, deviceID: Self.deviceID,
          highWater: highWater)
        return (repo, key)
      }
      let repo = try await Vault.create(
        databasePath: databasePath, password: password, params: params, deviceID: Self.deviceID,
        highWater: highWater)
      return (repo, nil)
    } catch {
      throw Self.map(error)
    }
  }

  /// Open the vault — runs the manifest + anti-rollback checks (§5.5).
  func unlock(password: Data) async throws -> VaultRepository {
    do {
      return try await Vault.unlock(
        databasePath: databasePath, password: password, deviceID: Self.deviceID,
        highWater: highWater)
    } catch {
      throw Self.map(error)
    }
  }

  /// Build this path's vault from a synced one (`Vault.join`): the server's header, unlocked with
  /// `password`, and sync configured. The first sync run downloads the records.
  func join(
    api: any SyncAPI, endpoint: URL, vaultID: UUID, password: Data, deviceID: UUID
  ) async throws -> VaultRepository {
    try await Vault.join(
      databasePath: databasePath, password: password, api: api, endpoint: endpoint,
      vaultID: vaultID, deviceID: deviceID, highWater: highWater)
  }

  /// The GUI's `verify --accept-restore`: clear the anti-rollback mark so the next
  /// `unlock` accepts the file and repairs the mark forward -- and, with sync on, reset
  /// the sync cursor so the next sync is a full resync (`m5-sync.md` A.10).
  func acceptRestoredBackup() async throws {
    try await Vault.acceptRestoredBackup(databasePath: databasePath, highWater: highWaterMark)
  }

  // MARK: - Replacing the vault

  /// The old vault's files, set aside to make room for another vault, and the mark they had.
  struct SetAside: Sendable, Equatable {
    /// Where the old vault's main file was kept.
    let kept: URL
    let mark: UInt64
  }

  /// Check `password` against the open vault's `header` with a second Argon2id pass -- the session
  /// can't check a password itself. Blocks ~500 ms -- call inside `Task.detached`.
  func verifyPassword(_ password: Data, header: Data) throws {
    do {
      _ = try VaultSession.open(header: header, password: password)
    } catch {
      throw Self.map(error)
    }
  }

  /// Move the vault's files aside as `vault.sqlite.<label>-<time>` (`pre-new`, `pre-load`), kept
  /// and never deleted, so another vault can take this path. The vault must be closed first.
  func setAside(label: String, now: Date = .now) throws -> SetAside {
    let mark = try highWaterMark.read()
    return SetAside(
      kept: try VaultMover.setAside(databasePath, label: label, now: now), mark: mark)
  }

  /// Undo `setAside`: remove whatever a failed create or install left at the path, return the old
  /// files, and restore their anti-rollback mark (a create resets it to 0 before it can fail).
  func putBack(_ aside: SetAside) {
    VaultMover.undoInstall(at: databasePath, restoring: aside.kept)
    try? highWaterMark.write(aside.mark)
  }

  /// Copy the vault file at `source` into a private scratch folder, with its `-wal` when there is
  /// one and it can be read, so a vault that wasn't closed cleanly loses nothing. Unlike a backup,
  /// a live vault is in WAL mode, and a lone copy of one can't be opened read-only (SQLite would
  /// have to create its `-shm`), so the copy is not inspected here: `checkVault` opens it.
  ///
  /// - Returns: the copy, `vault.sqlite` in the scratch folder.
  /// - Throws: `AppError.loadRefused` if the file isn't an SQLite database at all.
  func stageVault(from source: URL) throws -> URL {
    let fm = FileManager.default
    let path = source.path(percentEncoded: false)
    let magic = FileHandle(forReadingAtPath: path).flatMap { try? $0.read(upToCount: 16) }
    guard magic == Data("SQLite format 3\0".utf8) else {
      throw AppError.loadRefused("That file isn't a PassFort vault.")
    }
    let scratch = fm.temporaryDirectory
      .appending(path: "passfort-load-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fm.createDirectory(
      at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let staged = scratch.appending(path: "vault.sqlite")
    do {
      try fm.copyItem(atPath: path, toPath: staged.path(percentEncoded: false))
    } catch {
      try? fm.removeItem(at: scratch)
      throw AppError.io(error.localizedDescription)
    }
    // Best effort: outside its own storage the sandbox grants the chosen file, not its siblings.
    try? fm.copyItem(atPath: path + "-wal", toPath: staged.path(percentEncoded: false) + "-wal")
    return staged
  }

  /// Remove a copy made by `stageVault`, and its scratch folder.
  func discardStaged(_ staged: URL) {
    try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
  }

  /// Unlock a copy made by `stageVault`: it is a vault, the password is right, the manifest
  /// verifies, and the schema is one this version reads -- before anything is swapped. An older
  /// schema is migrated in the copy. The copy is closed again on return, its log folded into the
  /// main file. It runs against a throwaway mark beside the copy, so this vault's mark is not
  /// touched.
  func checkVault(at staged: URL, password: Data) async throws {
    let scratchMark = HighWaterMark(url: staged.appendingPathExtension("hw"))
    do {
      _ = try await Vault.unlock(
        databasePath: staged.path(percentEncoded: false), password: password,
        deviceID: Self.deviceID, highWater: scratchMark)
    } catch {
      throw Self.map(error)
    }
  }

  /// Put a checked, closed vault file at this path (which `setAside` emptied) and start the
  /// anti-rollback mark at its version. Not the old vault's mark: it belongs to a different vault,
  /// and keeping it would report the loaded one as rolled back.
  func install(_ staged: URL, version: UInt64) throws {
    let fm = FileManager.default
    let from = staged.path(percentEncoded: false)
    for suffix in ["", "-wal", "-shm"] where fm.fileExists(atPath: from + suffix) {
      try fm.moveItem(atPath: from + suffix, toPath: databasePath + suffix)
    }
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databasePath)
    try highWaterMark.write(version)
  }

  /// Unlock another vault read-only and read the accounts it could bring into `target`
  /// (`VaultImport.plan`). The source file is not changed.
  func planImport(
    fromVaultAt path: String, unlockingWith credential: VaultImport.Credential,
    into target: VaultRepository
  ) async throws -> ImportPlan {
    do {
      return try await VaultImport.plan(
        fromVaultAt: path, unlockingWith: credential, into: target)
    } catch PassFortError.notFound {
      throw AppError.importRefused("That vault has no recovery key. Unlock it with its password.")
    } catch {
      throw Self.map(error)
    }
  }

  // MARK: - Error translation

  static func map(_ error: Error) -> AppError {
    switch error {
    case VaultImport.Failure.notAVault:
      return .importRefused("That file isn't a PassFort vault.")
    case VaultImport.Failure.sameVault:
      return .importRefused("That's this vault, or a copy of it. There's nothing to import.")
    case VaultImport.Failure.unsupportedSchema:
      return .importRefused(
        "That vault is from a different version of PassFort, so this one can't read it.")
    case PassFortError.authFailed:
      return .wrongPassword
    case VaultError.notFound:
      return .notAVault
    case VaultManifest.Failure.macMismatch:
      return .tampered
    case VaultManifest.Failure.rollbackDetected(let fileVersion, let lastSeen):
      return .rolledBack(fileVersion: fileVersion, lastSeen: lastSeen)
    default:
      return .io(String(describing: error))
    }
  }
}
