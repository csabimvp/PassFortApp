import Foundation
import PassFortVault
import SwiftUI

/// The `.unlocked` screen, in three columns: the sidebar picks a slice (`SidebarItem`), the middle
/// column lists it — accounts with copy buttons, health findings, or deleted accounts — and the
/// detail column shows the account selected there. Everything listed comes from `model.summaries`,
/// the §8.3 in-memory index (decrypted titles, no secrets); copying decrypts one record on demand.
struct VaultListView: View {
  @Environment(AppModel.self) private var model
  @State private var sidebar: SidebarItem = .all
  @State private var selection: UUID?
  @State private var query = ""
  @State private var showingAdd = false
  @State private var editing: AccountSummary?
  @State private var deleting: AccountSummary?
  @State private var deleteError: String?
  @State private var togglingFavorite = false
  @State private var copyError: String?
  /// The confirmation under the list after a copy ("Password copied…"), cleared after a moment.
  @State private var copied: String?
  /// The last audit; re-run after every write. `nil` until the first run finishes.
  @State private var findings: [AuditFinding]?
  @FocusState private var searchFocused: Bool

  /// The narrowest the list column may get. Its part of the toolbar holds the title, whose view
  /// never shrinks below 160 pt however short the title, and the search field. When the column is
  /// narrower than those need, the toolbar pushes its separator past the column divider and the
  /// two stop lining up -- and the width is restored at the next launch, so it starts that way.
  static let contentMinWidth: CGFloat = 160 + ColumnSearchField.width + 20

  private var rows: [AccountSummary] {
    accountRows(from: model.summaries, in: sidebar, query: query)
  }

  private var selectedSummary: AccountSummary? {
    selection.flatMap { id in model.summaries.first { $0.id == id && !$0.isDeleted } }
  }

  var body: some View {
    NavigationSplitView {
      VaultSidebar(selection: $sidebar, healthCount: findings?.count)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    } content: {
      content
        .navigationTitle(sidebar.title)
        .navigationSplitViewColumnWidth(min: Self.contentMinWidth, ideal: 400, max: 560)
        .toolbar {
          // In this column's part of the toolbar, beside its title, as the mockup has it.
          ToolbarItem {
            ColumnSearchField(query: $query, focused: $searchFocused)
          }
          // The field draws its own background; no glass capsule around it.
          .sharedBackgroundVisibility(.hidden)
        }
        .background {
          // A ⌘F shortcut into the search field, not a toolbar button.
          Button("Search") { searchFocused = true }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    } detail: {
      Group {
        if let id = selection {
          AccountDetailView(accountID: id) { selection = $0 }
        } else {
          ContentUnavailableView("Select an account", systemImage: "key")
        }
      }
      .navigationSplitViewColumnWidth(min: 400, ideal: 560)
      .toolbar { toolbar }
    }
    .focusedSceneValue(\.accountActions, selectedSummary.map(actions(for:)))
    .onChange(of: sidebar) { selection = nil }
    .task(id: model.writeCounter) {
      if case .success(let result) = await model.audit() { findings = result }
    }
    .sheet(isPresented: $showingAdd) {
      AccountFormView(mode: .create)
    }
    .sheet(item: $editing) { summary in
      EditAccountSheet(id: summary.id)
    }
    .sheet(isPresented: Binding(get: { model.showingImport }, set: { model.showingImport = $0 })) {
      ImportView()
    }
    .sheet(
      isPresented: Binding(
        get: { model.showingVaultImport }, set: { model.showingVaultImport = $0 })
    ) {
      VaultImportView()
    }
    .confirmationDialog(
      "Delete “\(deleting?.title ?? "")”?",
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible, presenting: deleting
    ) { summary in
      Button("Delete", role: .destructive) { Task { await delete(summary) } }
    } message: { _ in
      Text("It moves to Recently Deleted, where you can restore it until you empty it.")
    }
    .sheet(
      item: Binding(
        get: { model.sync?.problemToShow.map(PresentedProblem.init) },
        set: { if $0 == nil { model.sync?.dismissProblem() } })
    ) { presented in
      SyncProblemSheet(problem: presented.problem) {
        Task { await model.sync?.syncNow() }
      }
    }
    .alert(
      "Couldn't copy",
      isPresented: Binding(get: { copyError != nil }, set: { if !$0 { copyError = nil } })
    ) {
      Button("OK") { copyError = nil }
    } message: {
      Text(copyError ?? "")
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

  // MARK: - Middle column

  @ViewBuilder
  private var content: some View {
    switch sidebar {
    case .health:
      HealthColumn(findings: findings, query: query, selection: $selection)
    case .deleted:
      DeletedColumn(query: query, selection: $selection)
    case .all, .favorites, .category, .tag, .conflicts:
      accountList
    }
  }

  private var accountList: some View {
    List(selection: $selection) {
      ForEach(rows) { row in
        AccountRow(row: row, isSelected: selection == row.id) { field in
          Task { await copy(field, of: row) }
        }
        .tag(row.id)
        .contextMenu { contextMenu(for: row) }
      }
    }
    .onDeleteCommand { if let selectedSummary { deleting = selectedSummary } }
    .overlay {
      if model.summaries.allSatisfy(\.isDeleted) {
        ContentUnavailableView {
          Label("No accounts yet", systemImage: "key")
        } actions: {
          Button("Import from Password Safe…") { model.showingImport = true }
          Button("Import from Another Vault…") { model.showingVaultImport = true }
        }
      } else if rows.isEmpty {
        ContentUnavailableView(
          query.isEmpty ? "Nothing here" : "No matches",
          systemImage: query.isEmpty ? "tray" : "magnifyingglass")
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Group {
        if let copied {
          Toast(text: copied)
        } else {
          Text(
            "\(AccountCommands.copyPasswordHint) password   "
              + "\(AccountCommands.copyUsernameHint) username   "
              + "\(AccountCommands.copyCodeHint) code"
          )
          .foregroundStyle(.secondary)
        }
      }
      .font(.caption)
      .frame(maxWidth: .infinity)
      .padding(6)
      .background(.bar)
    }
  }

  @ViewBuilder
  private func contextMenu(for row: AccountSummary) -> some View {
    if row.hasPassword {
      Button("Copy Password") { Task { await copy(.password, of: row) } }
    }
    if row.username != nil {
      Button("Copy Username") { Task { await copy(.username, of: row) } }
    }
    if row.hasOneTimeCode {
      Button("Copy One-Time Code") { Task { await copy(.oneTimeCode, of: row) } }
    }
    Divider()
    Button("Edit…") { editing = row }
    Button("Delete…", role: .destructive) { deleting = row }
  }

  /// Above the detail column, trailing, in the mockup's order: the selected account's star and
  /// Edit, then add / generate / lock in a group of their own. One builder, because SwiftUI puts
  /// an outer view's items before an inner one's, so the detail view can't contribute the first.
  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarSpacer(.flexible)
    if let summary = selectedSummary {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          Task { await toggleFavorite(summary) }
        } label: {
          Label(
            summary.favorite ? "Remove Favorite" : "Mark as Favorite",
            systemImage: summary.favorite ? "star.fill" : "star"
          )
          .foregroundStyle(summary.favorite ? Palette.favorite : Color.primary)
        }
        .disabled(togglingFavorite)
        .help(summary.favorite ? "Remove from Favorites" : "Add to Favorites")

        Button("Edit") { editing = summary }
      }
      ToolbarSpacer(.fixed, placement: .primaryAction)
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        showingAdd = true
      } label: {
        Label("Add account", systemImage: "plus")
      }
      .keyboardShortcut("n", modifiers: .command)
      .help("Add account (⌘N)")
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        model.showingGenerator = true
      } label: {
        Label("Generate password", systemImage: "wand.and.stars")
      }
      .help("Generate password (⌘⌥G)")
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        model.lock()
      } label: {
        Label("Lock", systemImage: "lock")
      }
      .keyboardShortcut("l", modifiers: .command)
      .help("Lock (⌘L)")
    }
  }

  // MARK: - Actions

  private func actions(for row: AccountSummary) -> AccountActions {
    AccountActions(
      copy: { field in Task { await copy(field, of: row) } },
      edit: { editing = row },
      delete: { deleting = row })
  }

  /// Flip the favorite flag: decrypt the one account, write it back with the flag toggled.
  private func toggleFavorite(_ summary: AccountSummary) async {
    guard !togglingFavorite else { return }
    togglingFavorite = true
    defer { togglingFavorite = false }
    guard case .loaded(let account) = await model.loadAccount(id: summary.id) else { return }
    var payload = account.payload
    payload.favorite.toggle()
    _ = await model.updateAccount(id: summary.id, to: payload)
  }

  private func delete(_ summary: AccountSummary) async {
    if let failure = await model.deleteAccount(id: summary.id) {
      deleteError = failure.message
    } else if selection == summary.id {
      selection = nil
    }
  }

  /// One decrypt, straight to the clipboard (concealed, cleared after the Settings delay or on
  /// lock); the plaintext is not kept. Confirms under the list; a failure (no such field) is an
  /// alert.
  private func copy(_ field: AppModel.CopyField, of summary: AccountSummary) async {
    if let failure = await model.copy(field, from: summary.id) {
      copyError = failure.message
      return
    }
    let message =
      "\(field.name.prefix(1).uppercased())\(field.name.dropFirst()) of "
      + "“\(summary.title)” copied — clears in \(Pasteboard.clearAfterDescription)"
    copied = message
    try? await Task.sleep(for: .seconds(2))
    if copied == message { copied = nil }
  }
}

/// A paused sync's problem, as a sheet item.
private struct PresentedProblem: Identifiable {
  let problem: SyncError
  var id: String { String(describing: problem) }
}

/// The edit form for an account picked from a context menu or ⌘E: decrypts it once, then hands
/// over to the same `AccountFormView` the detail column uses.
private struct EditAccountSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let id: UUID
  @State private var load: AppModel.AccountLoad?

  var body: some View {
    Group {
      switch load {
      case .loaded(let account):
        AccountFormView(mode: .edit(account))
      case .missing:
        unavailable("This account no longer exists.")
      case .failed(let message):
        unavailable(message)
      case nil:
        ProgressView().padding(40)
      }
    }
    .task { load = await model.loadAccount(id: id) }
    .onDisappear { load = nil }
  }

  private func unavailable(_ message: String) -> some View {
    VStack(spacing: 16) {
      ContentUnavailableView(
        "Can't edit this account", systemImage: "exclamationmark.lock",
        description: Text(message))
      Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
    }
    .padding()
    .frame(width: 360, height: 260)
  }
}

#Preview {
  VaultListView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
