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
  @State private var editing: AccountSummary?
  @State private var deleting: AccountSummary?
  @State private var deleteError: String?
  @FocusState private var searchFocused: Bool

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
      .searchFocused($searchFocused)
      .background {
        // Not in the toolbar (it showed up there as an empty button): just a ⌘F shortcut.
        Button("Search") { searchFocused = true }
          .keyboardShortcut("f", modifiers: .command)
          .opacity(0)
          .frame(width: 0, height: 0)
          .accessibilityHidden(true)
      }
      .onDeleteCommand { deleteSelected() }
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
            SettingsLink {
              Label("Settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
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
          .keyboardShortcut("n", modifiers: .command)
          .help("Add account (⌘N)")
        }
        ToolbarItem {
          Button {
            model.showingGenerator = true
          } label: {
            Label("Generate password", systemImage: "wand.and.stars")
          }
          .help("Generate password (⌘⌥G)")
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
    .sheet(isPresented: $showingAdd) {
      AccountFormView(mode: .create)
    }
    .sheet(item: $editing) { summary in
      EditAccountSheet(id: summary.id)
    }
    .confirmationDialog(
      "Delete “\(deleting?.title ?? "")”?",
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible, presenting: deleting
    ) { summary in
      Button("Delete", role: .destructive) { Task { await delete(summary) } }
    } message: { _ in
      Text("This removes the account from the vault. A backup made earlier still has it.")
    }
    .alert(
      "Couldn't delete the account",
      isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    ) {
      Button("OK") { deleteError = nil }
    } message: {
      Text(deleteError ?? "")
    }
  }

  private func deleteSelected() {
    guard let selection, let summary = model.summaries.first(where: { $0.id == selection })
    else { return }
    deleting = summary
  }

  private func delete(_ summary: AccountSummary) async {
    if let failure = await model.deleteAccount(id: summary.id) {
      deleteError = failure.message
    } else if selection == summary.id {
      selection = nil
    }
  }

  /// One decrypt, straight to the clipboard (concealed, cleared after 20 s or on lock); the
  /// plaintext is not kept.
  private func copyPassword(of summary: AccountSummary) async {
    let account = try? await model.repo?.account(id: summary.id)
    guard let password = account?.payload.password else { return }
    Pasteboard.copyTransient(password)
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
    .contextMenu {
      Button("Copy Password") { Task { await copyPassword(of: row) } }
      if let username = row.username {
        Button("Copy Username") { Pasteboard.copyTransient(username) }
      }
      Divider()
      Button("Edit…") { editing = row }
      Button("Delete…", role: .destructive) { deleting = row }
    }
  }
}

/// The edit form for an account picked from the sidebar's context menu: decrypts it once, then
/// hands over to the same `AccountFormView` the detail pane uses.
private struct EditAccountSheet: View {
  @Environment(AppModel.self) private var model
  let id: UUID
  @State private var account: Account?

  var body: some View {
    Group {
      if let account {
        AccountFormView(mode: .edit(account))
      } else {
        ProgressView().padding(40)
      }
    }
    .task { account = try? await model.repo?.account(id: id) }
    .onDisappear { account = nil }
  }
}

#Preview {
  VaultListView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
