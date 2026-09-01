import Foundation
import GRDB
import PassFortCrypto

/// The anti-rollback MAC over the whole record set (§5.5). Per-record AEAD proves
/// each row is intact; this proves the *set* hasn't been trimmed, reordered, or the
/// whole file rolled back to an older copy — the thing "most hobby password managers
/// get wrong" (§5.5).
///
/// The work splits along the async boundary on purpose: the row snapshot is read
/// synchronously on the database queue, then the HMAC streams through the C++
/// session (one hop to make the builder, then synchronous folds). Nothing here
/// `await`s inside a GRDB transaction closure — GRDB's closures are synchronous and
/// the `Database` handle must not escape them.
public enum VaultManifest {
  public enum Failure: Error, Equatable {
    /// The recomputed MAC doesn't match `vault_meta['manifest_mac']` — a row was
    /// added, removed, or edited outside a properly-transacted write.
    case macMismatch
    /// `vault_version` in the file is behind `highWater`, the value cached outside
    /// SQLite (§5.5; a sidecar file until M4 moves it to the Keychain). The file is
    /// internally consistent — row and MAC agree — but is an older copy than what
    /// this device last saw. A restored backup and an attacker's rollback are
    /// indistinguishable from inside the file alone; this is what tells them apart.
    case rollbackDetected(vaultVersion: UInt64, highWater: UInt64)
  }

  /// Recompute the manifest MAC over every row, at `vaultVersion`. Reads a
  /// consistent snapshot off the queue, then streams it through the session. Use
  /// for `passfort-cli verify` and tests; the Phase 6 write path folds rows through
  /// a `ManifestBuilder` it opens *before* its transaction instead, so the MAC
  /// covers exactly the post-write set in the same transaction.
  public static func compute(
    session: VaultSession, database: VaultDatabase, vaultVersion: UInt64
  ) async throws -> ManifestState {
    let rows = try await database.dbQueue.read { db in
      try SealedRecord.order(Column("uuid")).fetchAll(db)
    }
    return try await mac(session: session, sortedRows: rows, vaultVersion: vaultVersion)
  }

  /// At unlock: check `vault_version >= highWater` first — cheap, and it rejects a
  /// rolled-back file (whole-file swap, or a device that missed writes) before
  /// spending a full-vault MAC recompute on it. Only then recompute and compare the
  /// MAC, which catches a same-version tamper (a row added, removed, or edited
  /// outside a transacted write) that the version check alone can't see.
  @discardableResult
  public static func verifyAtUnlock(
    session: VaultSession, database: VaultDatabase, highWater: UInt64
  ) async throws -> ManifestState {
    let snapshot = try await database.dbQueue.read { db in
      Snapshot(
        vaultVersion: try VaultMeta.readVaultVersion(db),
        storedMAC: try VaultMeta.read(db, .manifestMAC),
        rows: try SealedRecord.order(Column("uuid")).fetchAll(db))
    }

    guard snapshot.vaultVersion >= highWater else {
      throw Failure.rollbackDetected(vaultVersion: snapshot.vaultVersion, highWater: highWater)
    }

    let computed = try await mac(
      session: session, sortedRows: snapshot.rows, vaultVersion: snapshot.vaultVersion)
    guard let storedMAC = snapshot.storedMAC, storedMAC == computed.mac else {
      throw Failure.macMismatch
    }
    return computed
  }

  // MARK: - Internal

  private struct Snapshot {
    var vaultVersion: UInt64
    var storedMAC: Data?
    var rows: [SealedRecord]
  }

  /// Fold a row snapshot into the MAC. `sortedRows` MUST be ascending by `uuid` —
  /// the MAC binds order (§5.5), so verify and compute have to agree on it.
  /// `vaultVersion` is bound into the tag (`HMAC(k, vault_version ‖ Σrows)`); the
  /// caller passes the version the stored MAC was made at (verify) or the one about
  /// to be stored (write), never a mix of the two.
  private static func mac(
    session: VaultSession, sortedRows: [SealedRecord], vaultVersion: UInt64
  ) async throws -> ManifestState {
    let builder = try await session.makeManifestBuilder(vaultVersion: vaultVersion)
    for row in sortedRows {
      try builder.update(recordID: row.id, version: row.version, sealed: row.sealed)
    }
    return ManifestState(vaultVersion: vaultVersion, mac: try builder.finish())
  }
}
