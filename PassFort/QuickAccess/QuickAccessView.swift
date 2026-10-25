import AppKit
import PassFortVault
import SwiftUI

/// Search, copy, get out of the way. Return copies the selected account's password, ⇧Return its
/// username, ⌥Return its one-time code; the window confirms it for a moment, then closes and
/// PassFort steps back so the app you came from is frontmost, ready to paste. Copies are transient (concealed, cleared after
/// the Settings delay or on lock).
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
          let field: AppModel.CopyField =
            press.modifiers.contains(.shift)
            ? .username : press.modifiers.contains(.option) ? .oneTimeCode : .password
          Task { await copy(field) }
          return .handled
        }

      if matches.isEmpty {
        Text(query.isEmpty ? "No accounts yet." : "No matches.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 60)
      } else {
        VStack(spacing: 2) {
          ForEach(matches) { row in
            AccountRow(row: row, isSelected: row.id == currentID) { field in
              selection = row.id
              Task { await copy(field) }
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
        Text("↩ password   ⇧↩ username   ⌥↩ one-time code   esc close")
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

  /// Copy, confirm for a moment -- long enough to see it worked, short enough not to wait on --
  /// then step back to the app you came from.
  private func copy(_ field: AppModel.CopyField) async {
    guard copied == nil, let id = currentID else { return }  // a second Return mid-confirmation
    if let failure = await model.copy(field, from: id) {
      message = failure.message
      return
    }
    message = nil
    let title = model.summaries.first { $0.id == id }?.title ?? ""
    let confirmation =
      "\(field.name.prefix(1).uppercased())\(field.name.dropFirst()) of “\(title)” copied — "
      + "clears in \(Pasteboard.clearAfterDescription)"
    copied = confirmation
    AccessibilityNotification.Announcement(confirmation).post()
    try? await Task.sleep(for: Self.confirmationDelay)
    copied = nil
    query = ""
    close()
  }

  static let confirmationDelay: Duration = .milliseconds(450)

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
