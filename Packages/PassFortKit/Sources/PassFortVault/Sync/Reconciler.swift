import Foundation

/// The A.7 merge rules (`m5-sync.md`): what to do with one pulled record, given the local row it
/// lands on. Pure and synchronous -- no I/O, no crypto, no clock. `SyncEngine` decrypts, seals and
/// stamps around it; this only decides.
///
/// `base` is the version the server last confirmed for the local row (`syncedVersion`), and the
/// row is dirty when its `version` has moved past it.
public enum Reconciler {

  /// The outcome for one pulled record. The engine turns it into rows of a `ReconcilePlan`.
  public enum Decision: Sendable, Equatable {
    /// Rule 1: no local row -- store the remote record as-is, clean.
    case insert
    /// Rules 2 and 4: an echo, a stale replay, or a server that hasn't moved past our base.
    /// Nothing changes.
    case ignore
    /// Rule 2 with equal versions: the echo of what this device already has. Only `synced_seq`
    /// moves.
    case confirm
    /// Rule 3: the local row is clean and the server is ahead -- overwrite it, clean.
    case fastForward
    /// Rules 5a, 5b, 5e and 5d when the remote side wins: overwrite the local row with the remote
    /// record, clean. With `copyLocal`, the local payload is saved first as a conflict copy.
    case takeRemote(copyLocal: Bool)
    /// Rules 5c and 5d when the local side wins: re-seal the local payload at
    /// `remote.version + 1`, based on `remote.version`, so the next push carries it. With
    /// `copyRemote`, the remote payload is saved as a conflict copy.
    case keepLocal(copyRemote: Bool)
  }

  /// Both sides' decrypted payloads -- needed only for a rule-5 conflict.
  public struct ConflictPayloads: Sendable {
    public var local: AccountPayload
    public var remote: AccountPayload

    public init(local: AccountPayload, remote: AccountPayload) {
      self.local = local
      self.remote = remote
    }
  }

  /// Rule 5: the local row changed since its base and the server moved past that base too. Only
  /// then does `decide` look at payloads, so only then does the engine decrypt the local row.
  public static func isConflict(local: SealedRecord?, remote: RecordDTO) -> Bool {
    guard let local, local.isDirty else { return false }
    return remote.version > (local.syncedVersion ?? 0)
  }

  /// Decide one pulled record (A.7 rows 1-5e).
  ///
  /// - Parameter payloads: both payloads, for a rule-5 conflict. Without them a conflict skips
  ///   the rule-5a "same edit on both sides" check and resolves by HLC, keeping a copy -- the
  ///   safe direction, never the lossy one.
  public static func decide(
    local: SealedRecord?, remote: RecordDTO, payloads: ConflictPayloads? = nil
  ) -> Decision {
    guard let local else { return .insert }  // 1

    guard local.isDirty else {
      if remote.version < local.version { return .ignore }  // 2: stale replay
      if remote.version == local.version { return .confirm }  // 2: echo
      return .fastForward  // 3
    }

    guard isConflict(local: local, remote: remote) else { return .ignore }  // 4

    // 5: both sides changed since the common base.
    if local.isDeleted && remote.isDeleted { return .takeRemote(copyLocal: false) }  // 5e
    if let payloads, local.isDeleted == remote.isDeleted,
      sameContent(payloads.local, payloads.remote)
    {
      return .takeRemote(copyLocal: false)  // 5a
    }
    // Not in A.7's table (Phase 10): one side has already seen the other's latest edit, so it
    // is a later state of the same record rather than a rival edit -- the later one wins with
    // nothing to copy. A restored backup's dirty rows hit this, and so does a row edited again
    // after a push whose response was lost.
    if let payloads {
      if descends(payloads.remote, from: payloads.local) { return .takeRemote(copyLocal: false) }
      if descends(payloads.local, from: payloads.remote) { return .keepLocal(copyRemote: false) }
    }
    // 5b / 5c, and 5d by the same token: the loser's payload survives as a copy unless the loser
    // is a tombstone -- a deletion that loses just means the record lives on.
    if remote.hlc.hlc > local.updatedAt {
      return .takeRemote(copyLocal: !local.isDeleted)
    }
    return .keepLocal(copyRemote: !remote.isDeleted)
  }

  /// Rule 5a's equality: the same content, whatever bookkeeping each side's edit wrote around it.
  /// Ignored: `revisionHistory` (each side stamps its own entry), `passwordChangedAt` and the
  /// `replacedAt` of password-history entries (both are "now" on the editing device). The
  /// replaced password values themselves still have to match.
  static func sameContent(_ a: AccountPayload, _ b: AccountPayload) -> Bool {
    normalized(a) == normalized(b)
  }

  /// `later` is a later state of `earlier`: its revision history holds `earlier`'s newest entry,
  /// and has moved past it. The history is sealed (only a DEK holder writes it), so a server
  /// can't fake this to make an edit disappear without a copy. A history capped past the entry
  /// (`revisionHistoryLimit`) just doesn't match -- and a copy is kept, the safe direction.
  static func descends(_ later: AccountPayload, from earlier: AccountPayload) -> Bool {
    guard let mark = earlier.revisionHistory.first, later.revisionHistory.first != mark else {
      return false
    }
    return later.revisionHistory.contains(mark)
  }

  private static func normalized(_ payload: AccountPayload) -> AccountPayload {
    var payload = payload
    payload.revisionHistory = []
    payload.passwordChangedAt = nil
    payload.passwordHistory = payload.passwordHistory.map {
      PasswordHistoryEntry(password: $0.password, replacedAt: .distantPast)
    }
    return payload
  }
}

/// What one ingest writes (`VaultRepository.applyRemote`): every row already sealed, so the
/// transaction does no crypto beyond the manifest fold.
public struct ReconcilePlan: Sendable, Equatable {
  /// The local `vault_version` the plan was built against. If a local write landed since,
  /// `applyRemote` refuses with `VaultError.staleWrite` and the engine plans the page again.
  public var vaultVersion: UInt64
  /// Rows written whole -- inserts, overwrites and re-sealed local winners -- with their sync
  /// columns set.
  public var rows: [SealedRecord] = []
  /// New records holding a losing side's payload (A.7). Dirty: the next push uploads them.
  public var conflictCopies: [SealedRecord] = []
  /// Echoes: rows whose content stays and whose `synced_version` / `synced_seq` move.
  public var confirmations: [PushedRecord] = []

  public init(vaultVersion: UInt64) {
    self.vaultVersion = vaultVersion
  }

  /// Nothing the manifest covers changes: only bookkeeping and the cursor.
  var isBookkeepingOnly: Bool { rows.isEmpty && conflictCopies.isEmpty }
}
