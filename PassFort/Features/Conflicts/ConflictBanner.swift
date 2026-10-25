import PassFortVault
import SwiftUI

/// The top of a conflict copy's detail (`m5-sync.md` A.11): what it is, and the three ways to
/// settle it. Two devices changed the same account before syncing; one change won, and the
/// other was kept here so nothing is lost.
struct ConflictBanner: View {
  @Environment(AppModel.self) private var model
  let copy: Account
  let select: (UUID?) -> Void

  @State private var working = false
  @State private var error: String?

  private var originalID: UUID? { copy.payload.conflictOf }

  /// The account the copy was split from, from the index; `nil` if it is gone altogether.
  private var original: AccountSummary? {
    originalID.flatMap { id in model.summaries.first { $0.id == id } }
  }

  private var made: Date {
    copy.payload.revisionHistory.first { $0.changed.contains("conflict copy") }?.at
      ?? copy.payload.createdAt
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        Text("Conflicting copy").font(.headline)
      } icon: {
        Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.warning)
      }
      Text(explanation)
        .font(.callout).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if let error {
        Label(error, systemImage: "xmark.octagon")
          .font(.callout).foregroundStyle(Palette.danger)
      }

      HStack {
        Button("Keep This Version") { resolve(.keepCopy) }
          .help("This copy replaces the other version, and the copy goes.")
        Button(original?.isDeleted == false ? "Keep the Other" : "Accept the Delete") {
          resolve(.keepOriginal)
        }
        .help("The other version stays as it is, and this copy goes.")
        Button("Keep Both") { resolve(.keepBoth) }
          .help("This copy becomes an account of its own.")
        Spacer()
      }
      .disabled(working)
    }
    .padding(.vertical, 4)
  }

  private var explanation: String {
    let when = made.formatted(date: .abbreviated, time: .shortened)
    let start =
      "Made by a sync conflict on \(when): this account was changed on two devices before they "
      + "synced. "
    switch original {
    case .some(let other) where !other.isDeleted:
      return start + "The other change is in “\(other.title)”."
    case .some:
      return start + "The other device deleted it; this copy keeps the change."
    case .none:
      return start + "The other version was deleted; this copy keeps the change."
    }
  }

  private func resolve(_ resolution: VaultRepository.ConflictResolution) {
    working = true
    error = nil
    // Where the selection goes once the copy is settled: the account that remains.
    let next: UUID? =
      switch resolution {
      case .keepCopy: original == nil ? copy.id : originalID
      case .keepOriginal: original?.isDeleted == false ? originalID : nil
      case .keepBoth: copy.id
      }
    Task {
      if let failure = await model.resolveConflict(copy: copy.id, resolution) {
        error = failure.message
      } else {
        select(next)
      }
      working = false
    }
  }
}
