import AppKit
import PassFortVault
import SwiftUI

/// Search, copy, get out of the way. Return copies the selected account's password, ⇧Return its
/// username, ⌥Return its one-time code; ⌘Return opens its website and queues the username, then
/// the password, one per paste (`AppModel.openAndFill`). The window confirms it for a moment, then
/// closes and PassFort steps back so the app you came from (or the opened site) is frontmost, ready
/// to paste. Copies are transient (concealed, cleared after the Settings delay or on lock).
///
/// It *deactivates* rather than hides: hiding would trip lock-on-background, and locking clears
/// the very clipboard entry just written.
struct QuickAccessView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismissWindow) private var dismissWindow

  @State private var query = ""
  @State private var selection: AccountSummary.ID?
  @State private var message: String?
  /// The confirmation shown for a moment after a copy, before the window steps back.
  @State private var copied: String?
  @State private var password = ""
  @FocusState private var focused: Bool

  private var matches: [AccountSummary] { quickMatches(from: model.summaries, query: query) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if case .unlocked = model.state {
        search
      } else {
        unlock
      }
      if let message {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(width: 420)
    .onAppear { focused = true }
    .onExitCommand { close() }
  }

  // MARK: - Unlocked

  private var search: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Search accounts", text: $query)
        .textFieldStyle(.roundedBorder)
        .font(.title3)
        .focused($focused)
        .onChange(of: query) { selection = matches.first?.id }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.return, phases: .down) { press in
          Task { await perform(Action(press.modifiers)) }
          return .handled
        }

      if matches.isEmpty {
        Text(query.isEmpty ? "No accounts yet." : "No matches.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 60)
      } else {
        VStack(spacing: 2) {
          ForEach(matches) { row in
            AccountRow(
              row: row, isSelected: row.id == currentID,
              fill: {
                selection = row.id
                Task { await perform(.fill) }
              }
            ) { field in
              selection = row.id
              Task { await perform(.copy(field)) }
            }
            .padding(.horizontal, 8)
            .background(
              row.id == currentID ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
              in: RoundedRectangle(cornerRadius: 6))
          }
        }
      }

      if let copied {
        Toast(text: copied).frame(maxWidth: .infinity)
      } else {
        Text("↩ password  ⇧↩ username  ⌥↩ code  ⌘↩ open & fill  esc close")
          .font(.caption2).foregroundStyle(.tertiary)
      }
    }
    .onAppear { selection = matches.first?.id }
  }

  private var currentID: AccountSummary.ID? {
    if let selection, matches.contains(where: { $0.id == selection }) { return selection }
    return matches.first?.id
  }

  private func move(_ offset: Int) -> KeyPress.Result {
    guard !matches.isEmpty else { return .ignored }
    let index = matches.firstIndex { $0.id == currentID } ?? 0
    selection = matches[min(max(index + offset, 0), matches.count - 1)].id
    return .handled
  }

  /// What Return does, by its modifiers -- or a row's button.
  enum Action: Equatable {
    case copy(AppModel.CopyField)
    case fill

    init(_ modifiers: EventModifiers) {
      if modifiers.contains(.command) {
        self = .fill
      } else if modifiers.contains(.shift) {
        self = .copy(.username)
      } else if modifiers.contains(.option) {
        self = .copy(.oneTimeCode)
      } else {
        self = .copy(.password)
      }
    }
  }

  /// Copy (or open and fill), confirm for a moment -- long enough to see it worked, short enough
  /// not to wait on -- then step back to the app you came from.
  private func perform(_ action: Action) async {
    guard copied == nil, let id = currentID else { return }  // a second Return mid-confirmation
    let title = model.summaries.first { $0.id == id }?.title ?? ""
    let confirmation: String
    switch action {
    case .copy(let field):
      if let failure = await model.copy(field, from: id) {
        message = failure.message
        return
      }
      confirmation =
        "\(field.name.prefix(1).uppercased())\(field.name.dropFirst()) of “\(title)” copied — "
        + "clears in \(Pasteboard.clearAfterDescription)"
    case .fill:
      switch await model.openAndFill(from: id) {
      case .failure(let failure):
        message = failure.message
        return
      case .success(let fill):
        confirmation = Self.confirmation(for: fill, title: title)
      }
    }
    message = nil
    copied = confirmation
    AccessibilityNotification.Announcement(confirmation).post()
    try? await Task.sleep(for: Self.confirmationDelay)
    copied = nil
    query = ""
    close()
  }

  static let confirmationDelay: Duration = .milliseconds(450)

  /// "Opened github.com — paste the username, then the password". Names the site, so a paste
  /// into the wrong page is easier to catch: the clipboard can't tell who is pasting.
  static func confirmation(for fill: AppModel.Fill, title: String) -> String {
    let order = fill.fields.map { "the \($0.name)" }.joined(separator: ", then ")
    let lead = fill.opened.map { "Opened \($0)" } ?? "“\(title)”"
    return "\(lead) — paste \(order)"
  }

  private func close() {
    dismissWindow(id: QuickAccessController.windowID)
    NSApp.deactivate()  // back to the app that was frontmost — not hide(), see the type comment
  }

  // MARK: - Locked

  private var unlock: some View {
    HStack {
      Image(systemName: "lock.fill").foregroundStyle(.secondary)
      SecureField("Master password", text: $password)
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onSubmit {
          let bytes = Data(password.utf8)
          password = ""
          Task {
            await model.unlock(password: bytes)
            focused = true
          }
        }
        .disabled(model.state.isUnlocking)
      if model.state.isUnlocking { ProgressView().controlSize(.small) }
    }
    .overlay(alignment: .bottomLeading) {
      if case .locked(let error?) = model.state {
        Text(error.message).font(.caption).foregroundStyle(Palette.danger).offset(y: 18)
      }
    }
  }
}

#Preview {
  QuickAccessView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
