import PassFortVault
import SwiftUI

/// The first column: where to look. All and Favorites, the categories and tags in use, then the
/// two special lists. Counts come from the in-memory index (§8.3); the health count from the last
/// audit, once it has run.
struct VaultSidebar: View {
  @Environment(AppModel.self) private var model
  @Binding var selection: SidebarItem
  let healthCount: Int?

  var body: some View {
    List(selection: $selection) {
      Section {
        item(.all, symbol: "key", color: Palette.primary)
        item(.favorites, symbol: "star", color: Palette.favorite)
      }

      let categories = usedCategories(in: model.summaries)
      if categories.count > 1 {
        Section("Categories") {
          ForEach(categories, id: \.self) { category in
            item(
              .category(category), symbol: category.symbol,
              color: Palette.color(category.family))
          }
        }
      }

      let tags = usedTags(in: model.summaries)
      if !tags.isEmpty {
        Section("Tags") {
          ForEach(tags, id: \.self) { tag in
            item(.tag(tag), symbol: "tag", color: .secondary)
          }
        }
      }

      let conflicts = count(of: .conflicts, in: model.summaries)
      if conflicts > 0 {
        Section("Sync") {
          row(
            .conflicts, symbol: "arrow.triangle.branch", color: Palette.warning, count: conflicts,
            alert: true)
        }
      }

      Section {
        row(.health, symbol: "stethoscope", color: Palette.danger, count: healthCount, alert: true)
        row(.deleted, symbol: "trash", color: .secondary, count: model.deletedSummaries.count)
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      HStack {
        SyncStatusFooter()
        Spacer()
        SettingsLink {
          Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Settings (⌘,)")
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    }
  }

  private func item(_ item: SidebarItem, symbol: String, color: Color) -> some View {
    row(item, symbol: symbol, color: color, count: count(of: item, in: model.summaries))
  }

  /// A sidebar row whose icon carries meaning in colour: brand, favorite gold, a category family,
  /// danger for health. `alert` draws the count as a filled danger badge rather than grey text.
  private func row(
    _ item: SidebarItem, symbol: String, color: Color, count: Int?, alert: Bool = false
  ) -> some View {
    Label {
      HStack {
        Text(item.title)
        Spacer()
        if let count, count > 0 {
          if alert {
            Text("\(count)")
              .font(.caption2.weight(.semibold)).monospacedDigit()
              .foregroundStyle(.white)
              .padding(.horizontal, 6)
              .frame(minWidth: 18, minHeight: 16)
              .background(Palette.danger, in: Capsule())
          } else {
            Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
          }
        }
      }
    } icon: {
      // Outline glyphs throughout, as the mockup draws them; the sidebar would otherwise fill some
      // symbols and not others.
      Image(systemName: symbol).symbolVariant(.none).foregroundStyle(color)
    }
    .tag(item)
  }
}

extension AccountCategory {
  /// The sidebar icon for a category.
  var symbol: String {
    switch self {
    case .login: "person"
    case .bankAccount: "building.columns"
    case .paymentCard: "creditcard"
    case .identity: "person.text.rectangle"
    case .secureNote: "doc.text"
    case .wifi: "wifi"
    case .softwareLicense: "doc.badge.gearshape"
    case .server: "server.rack"
    case .database: "cylinder"
    case .apiCredential: "chevron.left.forwardslash.chevron.right"
    case .other: "square.grid.2x2"
    }
  }
}
