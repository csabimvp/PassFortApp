import PassFortVault
import SwiftUI

/// Deleted accounts are tombstones (§8.2) until the vault is compacted, so they can come back.
/// This sheet lists them, restores one, or empties the lot.
struct RecentlyDeletedView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var confirmingEmpty = false
  @State private var working = false
  @State private var error: String?

  var body: some View {
    VStack(spacing: 0) {
      List {
        ForEach(model.deletedSummaries) { row in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(row.title)
              Text("Deleted \(row.lastUpdated.formatted(.relative(presentation: .named)))")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") { Task { await restore(row) } }
          }
        }
      }
      .overlay {
        if model.deletedSummaries.isEmpty {
          ContentUnavailableView("Nothing deleted", systemImage: "trash")
        }
      }

      if let error {
        Label(error, systemImage: "xmark.octagon").foregroundStyle(.red).padding(.top, 8)
      }

      Divider()
      HStack {
        Button("Empty…", role: .destructive) { confirmingEmpty = true }
          .disabled(model.deletedSummaries.isEmpty)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
      .padding()
    }
    .frame(width: 420, height: 360)
    .disabled(working)
    .navigationTitle("Recently Deleted")
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
  }
}

#Preview {
  RecentlyDeletedView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
