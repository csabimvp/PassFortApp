import AppKit
import Observation
import SwiftUI

/// The short confirmations after an action: "… copied", or "… moved to Recently Deleted" with
/// Undo. The vault window has one, shown under the account list, so everything done there confirms
/// the same way: the list's icons and the Account menu (`VaultListView`), the detail column's copy
/// buttons (`CopyButton`), and the edit form's Delete. Settings and its sheets host their own
/// (`toastHost()`).
@MainActor @Observable
final class ToastCenter {
  /// A button on the toast, e.g. Undo.
  struct Action {
    let title: String
    let perform: @MainActor () -> Void
  }

  /// What the toast shows. Never holds a copied value itself.
  struct Notice {
    let message: String
    var systemImage = "checkmark.circle"
    var color: Color
    var action: Action?
  }

  /// The toast on screen, or `nil`.
  private(set) var notice: Notice?
  var message: String? { notice?.message }

  @ObservationIgnored private let duration: Duration
  @ObservationIgnored private let actionDuration: Duration
  @ObservationIgnored private var clearing: Task<Void, Never>?

  /// A toast with a button stays longer (`actionDuration`), long enough to reach for it.
  init(duration: Duration = .seconds(2), actionDuration: Duration = .seconds(6)) {
    self.duration = duration
    self.actionDuration = actionDuration
  }

  /// Show `message` for a moment, and tell VoiceOver; a newer one replaces it and restarts the
  /// clock. `color` is `Palette.success` unless given: it is looked up here, not as a default
  /// argument, because `Palette` is main-actor isolated and a default is evaluated outside it.
  func show(
    _ message: String, systemImage: String = "checkmark.circle", color: Color? = nil,
    action: Action? = nil
  ) {
    notice = Notice(
      message: message, systemImage: systemImage, color: color ?? Palette.success, action: action)
    AccessibilityNotification.Announcement(message).post()
    clearing?.cancel()
    clearing = Task { [duration = action == nil ? duration : actionDuration] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      self.notice = nil
    }
  }

  /// The toast's button was pressed: take the toast down, then run the action -- once.
  func performAction() {
    guard let action = notice?.action else { return }
    dismiss()
    action.perform()
  }

  func dismiss() {
    clearing?.cancel()
    notice = nil
  }

  /// "“GitHub” moved to Recently Deleted", with Undo.
  func showDeleted(_ title: String, undo: @escaping @MainActor () -> Void) {
    show(
      "“\(title)” moved to Recently Deleted", systemImage: "trash", color: .secondary,
      action: Action(title: "Undo", perform: undo))
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
  @Environment(ToastCenter.self) private var notice: ToastCenter?
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
    let message = ToastCenter.message(copying: label, kind)
    if let notice {
      notice.show(message)
    } else {
      AccessibilityNotification.Announcement(message).post()
    }
    copied = true
  }
}

/// A window or sheet with no list footer to put the toast in (Settings, Add a Device): its own
/// `ToastCenter`, shown as the same capsule floating over the bottom edge. Its `CopyButton`s use it
/// instead of any notice further out, so a sheet's toast isn't hidden behind the sheet.
private struct ToastHost: ViewModifier {
  /// Distance from the bottom edge: a sheet with a button row lifts the toast above it.
  let bottomInset: CGFloat
  @State private var notice = ToastCenter()

  func body(content: Content) -> some View {
    content
      .environment(notice)
      .overlay(alignment: .bottom) {
        if let current = notice.notice {
          Toast(current) { notice.performAction() }
            .background(.regularMaterial, in: Capsule())  // legible over the form's rows
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .padding(.bottom, bottomInset)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .animation(.snappy(duration: 0.25), value: notice.message)
  }
}

extension View {
  /// Confirm copies made in this window or sheet with a floating toast (`ToastHost`).
  /// `bottomInset` lifts it clear of a sheet's button row.
  func toastHost(bottomInset: CGFloat = 14) -> some View {
    modifier(ToastHost(bottomInset: bottomInset))
  }
}

extension Toast {
  /// The toast for a `ToastCenter.Notice`; `perform` runs its button, if it has one.
  init(_ notice: ToastCenter.Notice, perform: @escaping () -> Void) {
    self.init(
      text: notice.message, systemImage: notice.systemImage, color: notice.color,
      actionTitle: notice.action?.title, onAction: perform)
  }
}
