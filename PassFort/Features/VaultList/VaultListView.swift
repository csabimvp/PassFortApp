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
  @State private var grouping: SidebarGrouping = .flat

  private var sections: [SidebarSection] {
    sidebarSections(from: model.summaries, query: query, grouping: grouping)
  }

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        ForEach(sections) { section in
          if let title = section.title {
            Section(title) {
              ForEach(section.rows) { row in
                rowLabel(row).tag(row.id)
              }
            }
          } else {
            // No header — keeps the plain flat list plain when grouping is off.
            Section {
              ForEach(section.rows) { row in
                rowLabel(row).tag(row.id)
              }
            }
          }
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .background(.ultraThinMaterial)
      .searchable(text: $query, prompt: "Search")
      .navigationTitle("PassFort")
      .navigationSplitViewColumnWidth(min: 220, ideal: 280)
      .overlay {
        if sections.isEmpty {
          ContentUnavailableView(
            query.isEmpty ? "No accounts yet" : "No matches",
            systemImage: query.isEmpty ? "key" : "magnifyingglass")
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(spacing: 0) {
          Divider()
          HStack {
            Menu {
              Picker("Group by", selection: $grouping) {
                ForEach(SidebarGrouping.allCases) { mode in
                  Text(mode.rawValue).tag(mode)
                }
              }
              .pickerStyle(.inline)
            } label: {
              Label(
                "Group By",
                systemImage: grouping == .flat
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
              )
              .labelStyle(.titleAndIcon)
              .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
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
        AccountDetailView(accountID: id)
      } else {
        ContentUnavailableView("Select an account", systemImage: "key")
      }
    }
    .pfBackground()
    .sheet(isPresented: $showingAdd) {
      AccountFormView(mode: .create)
    }
  }

  @ViewBuilder
  private func rowLabel(_ row: AccountSummary) -> some View {
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
}

#Preview {
  VaultListView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
