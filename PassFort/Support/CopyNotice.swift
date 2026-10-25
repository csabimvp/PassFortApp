import AppKit
import Observation
import SwiftUI

/// The vault window's "… copied" toast, under the account list. One per app, in the environment of
/// the vault window, so every copy there confirms the same way: the list's icons and the Account
/// menu (`VaultListView`) and the detail column's copy buttons (`CopyButton`). Windows without it
/// (Settings, sheets) get `CopyButton`'s inline checkmark only.
@MainActor @Observable
final class CopyNotice {
  /// The confirmation on screen, or `nil`. Never holds the copied value itself.
  private(set) var message: String?

  @ObservationIgnored private let duration: Duration
  @ObservationIgnored private var clearing: Task<Void, Never>?

  init(duration: Duration = .seconds(2)) {
    self.duration = duration
  }

  /// Show `message` for a moment, and tell VoiceOver; a newer one replaces it and restarts the
  /// clock.
  func show(_ message: String) {
    self.message = message
    AccessibilityNotification.Announcement(message).post()
    clearing?.cancel()
    clearing = Task { [duration] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      self.message = nil
    }
  }

  /// "Password copied — clears in 20 sec" for a secret, "Username copied" otherwise.
  static func message(copying label: String, _ kind: CopyKind) -> String {
    let what = label.prefix(1).uppercased() + label.dropFirst()
    switch kind {
    case .secret: return "\(what) copied — clears in \(Pasteboard.clearAfterDescription)"
    case .value, .plain: return "\(what) copied"
    }
  }
}

/// How a copy goes onto the clipboard.
enum CopyKind {
  /// A secret: concealed from clipboard managers, cleared after the Settings delay or on lock.
  case secret
  /// Account data that isn't secret on its own (a username, a URL): concealed, not cleared.
  case value
  /// Ordinary text with nothing private in it (a vault ID, an invite link).
  case plain
}

/// The copy icon used everywhere: copies `value` as `kind`, turns into a checkmark for a moment,
/// and shows the vault window's toast when there is one (VoiceOver hears it either way).
struct CopyButton: View {
  /// What is copied, as a label: "Password", "One-time code".
  let label: String
  let value: String
  var kind: CopyKind = .secret

  /// Optional: present in the vault window only.
  @Environment(CopyNotice.self) private var notice: CopyNotice?
  @State private var copied = false

  var body: some View {
    Button(
      copied ? "Copied" : "Copy \(label.lowercased())",
      systemImage: copied ? "checkmark" : "doc.on.doc", action: copy
    )
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
    .foregroundStyle(copied ? AnyShapeStyle(Palette.success) : AnyShapeStyle(.secondary))
    .contentTransition(.symbolEffect(.replace))
    .help(copied ? "Copied" : "Copy \(label.lowercased())")
    .task(id: copied) {
      guard copied else { return }
      try? await Task.sleep(for: .seconds(1.5))
      copied = false
    }
  }

  private func copy() {
    switch kind {
    case .secret: Pasteboard.copyTransient(value)
    case .value: Pasteboard.copy(value)
    case .plain:
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(value, forType: .string)
    }
    let message = CopyNotice.message(copying: label, kind)
    if let notice {
      notice.show(message)
    } else {
      AccessibilityNotification.Announcement(message).post()
    }
    copied = true
  }
}
