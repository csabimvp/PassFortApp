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
          databasePath: databasePath, password: password, params: params, deviceID: Self.deviceID)
        return (repo, key)
      }
      let repo = try await Vault.create(
        databasePath: databasePath, password: password, params: params, deviceID: Self.deviceID)
      return (repo, nil)
    } catch {
      throw Self.map(error)
    }
  }

  /// Open the vault — runs the manifest + anti-rollback checks (§5.5).
  func unlock(password: Data) async throws -> VaultRepository {
    do {
      return try await Vault.unlock(
        databasePath: databasePath, password: password, deviceID: Self.deviceID)
    } catch {
      throw Self.map(error)
    }
  }

  /// The GUI's `verify --accept-restore`: clear the anti-rollback sidecar so the
  /// next `unlock` accepts the file and repairs the mark forward.
  func acceptRestoredBackup() throws {
    try HighWaterMark(sidecarFor: databasePath).reset()
  }

  // MARK: - Error translation

  private static func map(_ error: Error) -> AppError {
    switch error {
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
