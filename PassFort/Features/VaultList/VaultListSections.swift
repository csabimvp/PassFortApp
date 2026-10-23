import Foundation
import PassFortVault

/// What the sidebar can select: a slice of the accounts, or one of the two special lists. The
/// middle column shows whatever is selected here; the detail column shows the account picked there.
enum SidebarItem: Hashable {
  case all
  case favorites
  case category(AccountCategory)
  case tag(String)
  case health
  case deleted

  var title: String {
    switch self {
    case .all: "All Accounts"
    case .favorites: "Favorites"
    case .category(let category): category.displayName
    case .tag(let tag): tag
    case .health: "Password Health"
    case .deleted: "Recently Deleted"
    }
  }

  /// `true` for the slices of live accounts -- the lists with copy buttons.
  var isAccountList: Bool {
    switch self {
    case .all, .favorites, .category, .tag: true
    case .health, .deleted: false
    }
  }
}

/// Does `row` match the search text? Title, username, host or tag, case-insensitively.
func matches(_ row: AccountSummary, query: String) -> Bool {
  let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
  if needle.isEmpty { return true }
  return row.title.lowercased().contains(needle)
    || (row.username?.lowercased().contains(needle) ?? false)
    || (row.host?.lowercased().contains(needle) ?? false)
    || row.tags.contains { $0.lowercased().contains(needle) }
}

/// The live accounts in `item`, filtered by `query`: favorites first, then by title. Empty for
/// `.health` and `.deleted`, which have lists of their own.
func accountRows(
  from summaries: [AccountSummary], in item: SidebarItem, query: String
) -> [AccountSummary] {
  let inSlice: (AccountSummary) -> Bool
  switch item {
  case .all: inSlice = { _ in true }
  case .favorites: inSlice = { $0.favorite }
  case .category(let category): inSlice = { $0.category == category }
  case .tag(let tag): inSlice = { $0.tags.contains(tag) }
  case .health, .deleted: return []
  }
  return summaries.filter { !$0.isDeleted && inSlice($0) && matches($0, query: query) }
    .sorted { a, b in
      if a.favorite != b.favorite { return a.favorite }
      return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
}

/// How many live accounts each sidebar slice holds, for the counts beside them.
func count(of item: SidebarItem, in summaries: [AccountSummary]) -> Int {
  accountRows(from: summaries, in: item, query: "").count
}

/// The categories that have at least one live account, in the enum's order.
func usedCategories(in summaries: [AccountSummary]) -> [AccountCategory] {
  let used = Set(summaries.filter { !$0.isDeleted }.map(\.category))
  return sidebarCategoryOrder.filter(used.contains)
}

/// Categories grouped by colour family, as the mockup lists them, so each hue reads as one block:
/// personal, money, network, tech, notes. A case missing here still shows, at the end.
let sidebarCategoryOrder: [AccountCategory] = {
  let grouped: [AccountCategory] = [
    .login, .identity, .bankAccount, .paymentCard, .wifi, .server, .database, .apiCredential,
    .softwareLicense, .secureNote, .other,
  ]
  return grouped + AccountCategory.allCases.filter { !grouped.contains($0) }
}()

/// Every tag on a live account, sorted.
func usedTags(in summaries: [AccountSummary]) -> [String] {
  Set(summaries.filter { !$0.isDeleted }.flatMap(\.tags))
    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

/// Quick Access results: live accounts matching `query`, best first — title prefix, then title
/// contains, then username / host / tag — favorites ahead within each tier. With no query, the
/// favorites then everything, alphabetically. At most `limit`.
func quickMatches(
  from summaries: [AccountSummary], query: String, limit: Int = 8
) -> [AccountSummary] {
  let needle = query.trimmingCharacters(in: .whitespaces).lowercased()

  func tier(_ row: AccountSummary) -> Int? {
    if needle.isEmpty { return 0 }
    let title = row.title.lowercased()
    if title.hasPrefix(needle) { return 0 }
    if title.contains(needle) { return 1 }
    if row.username?.lowercased().contains(needle) ?? false { return 2 }
    if row.host?.lowercased().contains(needle) ?? false { return 2 }
    if row.tags.contains(where: { $0.lowercased().contains(needle) }) { return 3 }
    return nil
  }

  let ranked = summaries.filter { !$0.isDeleted }.compactMap { row in
    tier(row).map { (row: row, tier: $0) }
  }
  let best = ranked.sorted { a, b in
    if a.tier != b.tier { return a.tier < b.tier }
    if a.row.favorite != b.row.favorite { return a.row.favorite }
    return a.row.title.localizedCaseInsensitiveCompare(b.row.title) == .orderedAscending
  }
  return best.prefix(limit).map(\.row)
}
