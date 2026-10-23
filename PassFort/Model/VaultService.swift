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
  /// Single device until M5 sync — matches `SealedRecord`'s M2 constant. M4/M5
  /// issue a real per-install id.
  static let deviceID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

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

  /// The GUI's `verify --accept-restore`: clear the anti-rollback sidecar so the
  /// next `unlock` accepts the file and repairs the mark forward.
  func acceptRestoredBackup() throws {
    try highWaterMark.reset()
  }

  // MARK: - Starting over

  /// The old vault's files, set aside to make room for a new vault, and the mark they had.
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

  /// Move the vault's files aside as `vault.sqlite.pre-new-<time>`, kept and never deleted, so a
  /// new vault can be created at this path. The vault must be closed first.
  func setAside(now: Date = .now) throws -> SetAside {
    let mark = try highWaterMark.read()
    return SetAside(
      kept: try VaultMover.setAside(databasePath, label: "pre-new", now: now), mark: mark)
  }

  /// Undo `setAside`: remove whatever a failed create left at the path, return the old files, and
  /// restore their anti-rollback mark (a create resets it to 0 before it can fail).
  func putBack(_ aside: SetAside) {
    VaultMover.undoInstall(at: databasePath, restoring: aside.kept)
    try? highWaterMark.write(aside.mark)
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
