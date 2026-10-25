import SwiftUI

/// What the Account menu can do to the selected account. The vault window publishes it as a
/// focused value while an account is selected; with nothing selected the menu items are disabled.
struct AccountActions {
  let copy: @MainActor (AppModel.CopyField) -> Void
  let edit: @MainActor () -> Void
  let delete: @MainActor () -> Void
}

extension FocusedValues {
  @Entry var accountActions: AccountActions?
}

/// The Account menu: the copy shortcuts the list's icons stand for, plus edit and delete. Menu
/// items rather than invisible buttons, so the shortcuts are discoverable.
struct AccountCommands: Commands {
  @FocusedValue(\.accountActions) private var actions

  /// The shortcuts, shown in the list's footer as well.
  static let copyPasswordHint = "⇧⌘C"
  static let copyUsernameHint = "⌘U"
  static let copyCodeHint = "⌃⌘C"

  var body: some Commands {
    CommandMenu("Account") {
      Group {
        Button("Copy Password") { actions?.copy(.password) }
          .keyboardShortcut("c", modifiers: [.command, .shift])
        Button("Copy Username") { actions?.copy(.username) }
          .keyboardShortcut("u", modifiers: .command)
        Button("Copy One-Time Code") { actions?.copy(.oneTimeCode) }
          .keyboardShortcut("c", modifiers: [.command, .control])
        Divider()
        Button("Edit…") { actions?.edit() }
          .keyboardShortcut("e", modifiers: .command)
        Button("Delete") { actions?.delete() }
          .keyboardShortcut(.delete, modifiers: .command)
      }
      // Every item needs a selection.
      .disabled(actions == nil)
    }
  }
}
