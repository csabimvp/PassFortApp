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

  public init(
    id: UUID, version: UInt64, updatedAt: HLC, isDeleted: Bool, payload: AccountPayload
  ) {
    self.id = id
    self.version = version
    self.updatedAt = updatedAt
    self.isDeleted = isDeleted
    self.payload = payload
  }

  public init(envelope: SealedRecord, payload: AccountPayload) {
    self.init(
      id: envelope.id, version: envelope.version, updatedAt: envelope.updatedAt,
      isDeleted: envelope.isDeleted, payload: payload)
  }
}

extension Account {
  /// The secret-free row for the in-memory index (§7.5).
  public var summary: AccountSummary {
    AccountSummary(
      id: id,
      title: payload.title,
      username: payload.username,
      host: payload.urls.first?.host(),
      tags: payload.tags,
      favorite: payload.favorite,
      isConflict: payload.conflictOf != nil,
      isDeleted: isDeleted)
  }
}
