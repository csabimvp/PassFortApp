import Foundation
import PassFortVault
import SwiftUI

/// The `.unlocked` screen: a `NavigationSplitView` over `model.summaries` — the
/// §8.3 in-memory index (decrypted titles, no secrets). Search and sort happen
/// here in Swift, exactly as `passfort-cli list` does.
struct VaultListView: View {
  @Environment(AppModel.self) private var model
  @State private var selection: AccountSummary.ID?
  @State private var query = ""
  @State private var showingAdd = false

  private var rows: [AccountSummary] {
    let live = model.summaries.filter { !$0.isDeleted }
    let matched: [AccountSummary]
    if query.isEmpty {
      matched = live
    } else {
      let needle = query.lowercased()
      matched = live.filter { row in
        row.title.lowercased().contains(needle)
          || (row.username?.lowercased().contains(needle) ?? false)
          || (row.host?.lowercased().contains(needle) ?? false)
          || row.tags.contains { $0.lowercased().contains(needle) }
      }
    }
    return matched.sorted {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  var body: some View {
    NavigationSplitView {
      List(rows, selection: $selection) { row in
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            if row.favorite {
              Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
            }
            Text(row.title)
          }
          if let subtitle = row.username ?? row.host {
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .searchable(text: $query, prompt: "Search")
      .navigationTitle("PassFort")
      .frame(minWidth: 240)
      .overlay {
        if rows.isEmpty {
          ContentUnavailableView(
            query.isEmpty ? "No accounts yet" : "No matches",
            systemImage: query.isEmpty ? "key" : "magnifyingglass")
        }
      }
      .toolbar {
        ToolbarItem {
          Button {
            showingAdd = true
          } label: {
            Label("Add account", systemImage: "plus")
          }
        }
        ToolbarItem {
          Button {
            model.lock()
          } label: {
            Label("Lock", systemImage: "lock")
          }
          .keyboardShortcut("l", modifiers: .command)
        }
      }
    } detail: {
      if let id = selection {
        // Phase 6 replaces this with AccountDetailView(accountID: id).
        ContentUnavailableView(
          "Account", systemImage: "doc.text",
          description: Text("\(id.uuidString)\nDetail view — Phase 6"))
      } else {
        ContentUnavailableView("Select an account", systemImage: "key")
      }
    }
    .frame(minWidth: 720, minHeight: 420)
    .sheet(isPresented: $showingAdd) {
      // Phase 7 replaces this with AccountFormView(mode: .create).
      VStack(spacing: 16) {
        Text("Add account").font(.headline)
        Text("Form — Phase 7").foregroundStyle(.secondary)
        Button("Close") { showingAdd = false }.keyboardShortcut(.cancelAction)
      }
      .padding(40)
    }
  }
}

#Preview {
  VaultListView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
