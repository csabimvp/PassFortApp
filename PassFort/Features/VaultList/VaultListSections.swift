import Foundation
import PassFortVault

/// How the sidebar arranges non-favorite rows. Favorites are always pinned in
/// their own section on top, regardless of this setting (§12).
enum SidebarGrouping: String, CaseIterable, Identifiable {
  case flat = "None"
  case category = "Category"

  var id: Self { self }
}

/// One `List` section: `title == nil` renders without a header, matching the
/// plain flat list this replaces when there's nothing to label.
struct SidebarSection: Identifiable {
  let id: String
  let title: String?
  let rows: [AccountSummary]
}

/// Builds the sidebar's sections from the live index: filters by `query`,
/// pins favorites on top, then arranges the rest per `grouping`. Pulled out of
/// `VaultListView` so it's plain, testable logic rather than view code.
func sidebarSections(
  from summaries: [AccountSummary], query: String, grouping: SidebarGrouping
) -> [SidebarSection] {
  let live = summaries.filter { !$0.isDeleted }
  let matched: [AccountSummary]
  if query.isEmpty {
    matched = live
  } else {
    let needle = query.lowercased()
    matched = live.filter { row in
      row.title.lowercased().contains(needle)
        || (row.username?.lowercased().contains(needle) ?? false)
        || (row.host?.lowercased().contains(needle) ?? false)
        || row.tags.contains { $0.lowercased().contains(needle) }
    }
  }

  func alphabetical(_ rows: [AccountSummary]) -> [AccountSummary] {
    rows.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  let favorites = alphabetical(matched.filter(\.favorite))
  let rest = matched.filter { !$0.favorite }

  var sections: [SidebarSection] = []
  if !favorites.isEmpty {
    sections.append(SidebarSection(id: "favorites", title: "Favorites", rows: favorites))
  }

  switch grouping {
  case .flat:
    if !rest.isEmpty {
      // No header when it's the only section (matches the original flat list);
      // otherwise it just continues, unlabeled, below "Favorites".
      sections.append(SidebarSection(id: "all", title: nil, rows: alphabetical(rest)))
    }
  case .category:
    for cat in AccountCategory.allCases {
      let rows = alphabetical(rest.filter { $0.category == cat })
      if !rows.isEmpty {
        sections.append(SidebarSection(id: cat.rawValue, title: cat.displayName, rows: rows))
      }
    }
  }

  return sections
}
