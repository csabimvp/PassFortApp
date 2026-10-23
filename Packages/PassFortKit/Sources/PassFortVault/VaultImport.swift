import Foundation
import GRDB
import PassFortCrypto

/// Copy accounts out of another PassFort vault into the open one (§7.6) -- a dev vault into the
/// everyday one, say.
///
/// The source is opened **read-only**: no migration, no anti-rollback sidecar write, no row
/// touched, and a recovery key opens it without consuming its slot. Its live accounts come out
/// decrypted into an `ImportPlan`, the shape a Password Safe import produces, and go in through
/// `VaultRepository.importAccounts`: re-sealed under this vault's DEK with new ids. A sealed blob
/// cannot be moved as is -- its AAD binds the record's id and version (§5.4), and its key is the
/// other vault's DEK. The plan is plaintext; keep it only while needed.
public enum VaultImport {
  public enum Failure: Error, Equatable {
    /// No file there, or the file holds no PassFort vault.
    case notAVault
    /// The source is the vault being imported into, or a copy of it (the same vault id).
    case sameVault
    /// The source's schema is not the one this build reads: older (open it with this build once
    /// to migrate it) or newer (written by a later PassFort).
    case unsupportedSchema
  }

  /// What unlocks the source vault.
  public enum Credential: Sendable {
    case password(Data)
    case recoveryKey(RecoveryKey)
  }

  /// Unlock the vault at `databasePath` read-only and read its live accounts, ordered by title.
  /// Deleted accounts are left behind and counted in `warnings`. Each payload drops its revision
  /// history (those versions belong to the source; `importAccounts` seeds `["imported"]`) and its
  /// `conflictOf` (an id in the source); password history and dates come across unchanged.
  ///
  /// - Parameter target: the vault the accounts are for -- only its id is read, to refuse a
  ///   self-import.
  /// - Throws: `Failure`; `PassFortError.authFailed` for a wrong credential;
  ///   `PassFortError.notFound` for a recovery key on a vault without a recovery slot;
  ///   `VaultManifest.Failure.macMismatch` if the source was edited outside PassFort.
  public static func plan(
    fromVaultAt databasePath: String, unlockingWith credential: Credential,
    into target: VaultRepository
  ) async throws -> ImportPlan {
    guard VaultDatabase.vaultExists(atPath: databasePath) else { throw Failure.notAVault }
    let database = try VaultDatabase(readOnlyAt: databasePath)
    guard try database.hasCurrentSchema else { throw Failure.unsupportedSchema }
    let header = try await database.dbQueue.read { db in
      guard let header = try VaultMeta.read(db, .header) else { throw Failure.notAVault }
      return header
    }

    let session: VaultSession
    switch credential {
    case .password(let password):
      session = try VaultSession.open(header: header, password: password)
    case .recoveryKey(let key):
      session = try VaultSession.openWithRecovery(header: header, recoveryKey: key.raw)
    }
    guard try await session.vaultUUID() != (try await target.vaultUUID()) else {
      throw Failure.sameVault
    }

    // The tamper half of the unlock check. The rollback half is skipped (a mark of 0): the
    // source's mark may sit in another build's storage, and a rolled-back source only means older
    // accounts to choose from -- nothing in either vault is overwritten.
    try await VaultManifest.verifyAtUnlock(session: session, database: database, highWater: 0)

    let records = try await database.dbQueue.read { db in
      try SealedRecord.order(Column("uuid")).fetchAll(db)
    }
    var payloads: [AccountPayload] = []
    for record in records where !record.isDeleted {
      var payload = try PayloadCodec.decode(
        try await session.open(
          recordID: record.id, version: record.version, schema: record.schemaVersion,
          sealed: record.sealed))
      payload.revisionHistory = []
      payload.conflictOf = nil
      payloads.append(payload)
    }
    payloads.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

    var plan = ImportPlan()
    plan.accounts = payloads.enumerated().map { ImportedAccount(line: $0 + 1, payload: $1) }
    let deleted = records.count - payloads.count
    if deleted > 0 {
      plan.warnings.append(
        "\(deleted) deleted account\(deleted == 1 ? " is" : "s are") not offered")
    }
    return plan
  }
}
