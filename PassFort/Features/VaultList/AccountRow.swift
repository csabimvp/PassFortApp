import PassFortVault
import SwiftUI

/// One account in a list: its category tile, title (starred if a favorite), the username or host
/// beneath, and copy buttons for what the account actually has (plus open-and-fill in Quick
/// Access). The buttons show only on the
/// selected or hovered row, as the mockup draws them, so the other titles get the full width; the
/// copy shortcuts and the VoiceOver actions work on every row regardless. Used by the vault's
/// middle column and by the Quick Access window, so both behave the same. The row holds no secret:
/// copying decrypts on demand.
struct AccountRow: View {
  let row: AccountSummary
  var isSelected = false
  /// Open the website and queue username then password (Quick Access's ⌘↩); its button shows
  /// only when given and the account has a web address.
  var fill: (() -> Void)?
  let copy: (AppModel.CopyField) -> Void

  @Environment(\.backgroundProminence) private var prominence
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 10) {
      CategoryTile(title: row.title, category: row.category)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(row.title).fontWeight(.medium).lineLimit(1)
          if row.isConflict {
            Image(systemName: "arrow.triangle.branch").font(.caption2)
              .foregroundStyle(prominence == .increased ? Color.white : Palette.warning)
              .accessibilityLabel("Conflicting copy")
              .help("A copy kept by a sync conflict")
          }
          if row.favorite {
            // White on a selected row, like the rest of its text.
            Image(systemName: "star.fill").font(.caption2)
              .foregroundStyle(prominence == .increased ? Color.white : Palette.favorite)
              .accessibilityLabel("Favorite")
          }
        }
        if let subtitle = row.username ?? row.host {
          Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      if isSelected || hovering {
        HStack(spacing: 2) {
          copyButton(
            "Copy username", symbol: "person", field: .username, enabled: row.username != nil)
          copyButton("Copy password", symbol: "key", field: .password, enabled: row.hasPassword)
          copyButton(
            "Copy one-time code", symbol: "clock", field: .oneTimeCode,
            enabled: row.hasOneTimeCode)
          if let fill {
            if row.host != nil {
              IconButton("Open website and fill", systemImage: "arrow.up.right.square") { fill() }
            } else {
              Image(systemName: "arrow.up.right.square").hidden()
            }
          }
        }
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .accessibilityActions {
      if row.hasPassword { Button("Copy password") { copy(.password) } }
      if row.username != nil { Button("Copy username") { copy(.username) } }
      if row.hasOneTimeCode { Button("Copy one-time code") { copy(.oneTimeCode) } }
      if let fill { Button(row.host != nil ? "Open website and fill" : "Fill") { fill() } }
    }
  }

  /// A borderless icon button; an absent field leaves an empty slot so the columns line up.
  @ViewBuilder
  private func copyButton(
    _ title: String, symbol: String, field: AppModel.CopyField, enabled: Bool
  ) -> some View {
    if enabled {
      IconButton(title, systemImage: symbol) { copy(field) }
    } else {
      Image(systemName: symbol).hidden()
    }
  }
}

#Preview {
  List {
    AccountRow(
      row: AccountSummary(
        id: UUID(), title: "GitHub", username: "me", favorite: true, lastUpdated: .now,
        hasPassword: true, hasOneTimeCode: true),
      isSelected: true
    ) { _ in }
    AccountRow(
      row: AccountSummary(
        id: UUID(), title: "Wi-Fi", category: .wifi, lastUpdated: .now, hasPassword: true)
    ) { _ in }
  }
}
