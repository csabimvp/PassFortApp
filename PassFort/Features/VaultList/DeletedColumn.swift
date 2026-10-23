import PassFortVault
import SwiftUI

/// The middle column for Recently Deleted. Deleted accounts are tombstones (§8.2) until the vault
/// is compacted, so each can be restored; "Empty" compacts them all.
struct DeletedColumn: View {
  @Environment(AppModel.self) private var model
  let query: String
  @Binding var selection: UUID?

  @State private var confirmingEmpty = false
  @State private var working = false
  @State private var error: String?

  private var rows: [AccountSummary] {
    model.deletedSummaries.filter { matches($0, query: query) }
  }

  var body: some View {
    List(selection: $selection) {
      ForEach(rows) { row in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
            Text("Deleted \(row.lastUpdated.formatted(.relative(presentation: .named)))")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Restore") { Task { await restore(row) } }
        }
        .tag(row.id)
      }
    }
    .overlay {
      if model.deletedSummaries.isEmpty {
        ContentUnavailableView("Nothing deleted", systemImage: "trash")
      } else if rows.isEmpty {
        ContentUnavailableView("No matches", systemImage: "magnifyingglass")
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      HStack {
        if let error {
          Label(error, systemImage: "xmark.octagon").foregroundStyle(Palette.danger).lineLimit(1)
        }
        Spacer()
        Button("Empty…", role: .destructive) { confirmingEmpty = true }
          .disabled(model.deletedSummaries.isEmpty)
      }
      .font(.caption)
      .padding(6)
      .background(.bar)
    }
    .disabled(working)
    .confirmationDialog(
      "Permanently erase \(model.deletedSummaries.count) deleted account(s)?",
      isPresented: $confirmingEmpty, titleVisibility: .visible
    ) {
      Button("Erase", role: .destructive) { Task { await empty() } }
    } message: {
      Text("They can't be restored afterwards. Backups made before now still contain them.")
    }
  }

  private func restore(_ row: AccountSummary) async {
    working = true
    defer { working = false }
    error = await model.restoreAccount(id: row.id)?.message
  }

  private func empty() async {
    working = true
    defer { working = false }
    error = await model.emptyRecentlyDeleted()?.message
    if error == nil { selection = nil }
  }
}
