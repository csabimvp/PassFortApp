import SwiftUI

/// The account list's search field, drawn in the list column's header beside its title rather
/// than at the window's trailing edge, as the mockup places it. ⌘F focuses it (the list view's
/// hidden shortcut), Escape clears it.
struct ColumnSearchField: View {
  /// Fixed: a toolbar item is laid out at its ideal width, so a flexible frame never shrinks it.
  /// `VaultListView.contentMinWidth` is derived from this.
  static let width: CGFloat = 180

  @Binding var query: String
  var focused: FocusState<Bool>.Binding

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField("Search", text: $query)
        .textFieldStyle(.plain)
        .focused(focused)
        .onExitCommand { query = "" }
      if !query.isEmpty {
        IconButton("Clear search", systemImage: "xmark.circle.fill") { query = "" }
      }
    }
    .padding(.horizontal, 8)
    .frame(width: Self.width, height: 28)
    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
  }
}
