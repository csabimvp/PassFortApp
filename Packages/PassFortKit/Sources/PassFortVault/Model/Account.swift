import Foundation

/// The envelope and the decrypted payload merged — what `VaultRepository` hands
/// the UI, held in memory only while the vault is unlocked (§7.2). `id` is the
/// record UUID (the payload carries no id of its own).
public struct Account: Sendable, Identifiable, Equatable {
  public var id: UUID
  public var version: UInt64
  public var updatedAt: HLC
  public var isDeleted: Bool
  public var payload: AccountPayload
  /// The record's §7.1 schema version -- the envelope field the payload was
  /// decoded against, not the payload's own `AccountPayload.schemaVersion`.
  public var schemaVersion: UInt16
  /// `sealed.count` from the envelope -- `nonce ‖ ciphertext ‖ tag`, i.e. what
  /// this record actually costs on disk. A UI "under the hood" stat only.
  public var sealedSize: Int

  public init(
    id: UUID, version: UInt64, updatedAt: HLC, isDeleted: Bool, payload: AccountPayload,
    schemaVersion: UInt16, sealedSize: Int
  ) {
    self.id = id
    self.version = version
    self.updatedAt = updatedAt
    self.isDeleted = isDeleted
    self.payload = payload
    self.schemaVersion = schemaVersion
    self.sealedSize = sealedSize
  }

  public init(envelope: SealedRecord, payload: AccountPayload) {
    self.init(
      id: envelope.id, version: envelope.version, updatedAt: envelope.updatedAt,
      isDeleted: envelope.isDeleted, payload: payload, schemaVersion: envelope.schemaVersion,
      sealedSize: envelope.sealed.count)
  }
}

extension Account {
  /// Wall-clock time of the last write to this record, read off the HLC envelope
  /// column (§7.4) — what a UI or `passfort-cli get` shows as "last updated".
  public var lastUpdated: Date {
    Date(timeIntervalSince1970: Double(updatedAt.wallMillis) / 1000)
  }

  /// The secret-free row for the in-memory index (§7.5).
  public var summary: AccountSummary {
    AccountSummary(
      id: id,
      title: payload.title,
      username: payload.username,
      host: payload.urls.first?.host(),
      tags: payload.tags,
      favorite: payload.favorite,
      category: payload.category,
      isConflict: payload.conflictOf != nil,
      isDeleted: isDeleted,
      lastUpdated: lastUpdated,
      hasPassword: payload.password?.isEmpty == false,
      hasOneTimeCode: payload.totp != nil)
  }
}
