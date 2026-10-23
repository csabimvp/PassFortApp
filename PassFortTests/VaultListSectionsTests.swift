import Foundation
import PassFortVault
import Testing

@testable import PassFort

/// The three-column vault window's list logic: what each sidebar slice shows, in what order, and
/// what the sidebar offers.
struct VaultListSectionsTests {

  private func summary(
    _ title: String, username: String? = nil, category: AccountCategory = .login,
    tags: [String] = [], favorite: Bool = false, deleted: Bool = false
  ) -> AccountSummary {
    AccountSummary(
      id: UUID(), title: title, username: username, tags: tags, favorite: favorite,
      category: category, isDeleted: deleted, lastUpdated: Date())
  }

  private var vault: [AccountSummary] {
    [
      summary("Zebra Bank", category: .bankAccount, tags: ["Finance/Banking"]),
      summary("apple", username: "me", favorite: true),
      summary("GitHub", username: "octo", tags: ["Work"]),
      summary("Home Wi-Fi", category: .secureNote),
      summary("Old", tags: ["Gone"], deleted: true),
    ]
  }

  @Test func allShowsLiveAccountsFavoritesFirstThenByTitle() {
    #expect(
      accountRows(from: vault, in: .all, query: "").map(\.title)
        == ["apple", "GitHub", "Home Wi-Fi", "Zebra Bank"])
  }

  @Test func eachSliceFiltersAndSearchNarrowsIt() {
    #expect(accountRows(from: vault, in: .favorites, query: "").map(\.title) == ["apple"])
    #expect(
      accountRows(from: vault, in: .category(.bankAccount), query: "").map(\.title)
        == ["Zebra Bank"])
    #expect(accountRows(from: vault, in: .tag("Work"), query: "").map(\.title) == ["GitHub"])
    #expect(accountRows(from: vault, in: .all, query: "OCTO").map(\.title) == ["GitHub"])
    #expect(accountRows(from: vault, in: .all, query: "banking").map(\.title) == ["Zebra Bank"])
    #expect(accountRows(from: vault, in: .health, query: "").isEmpty)
    #expect(accountRows(from: vault, in: .deleted, query: "").isEmpty)
  }

  @Test func theSidebarOffersOnlyWhatLiveAccountsUse() {
    #expect(usedCategories(in: vault) == [.login, .bankAccount, .secureNote])
    #expect(usedTags(in: vault) == ["Finance/Banking", "Work"])  // "Gone" is only on a tombstone
    #expect(count(of: .all, in: vault) == 4)
    #expect(count(of: .favorites, in: vault) == 1)
  }

  @Test func onlyTheAccountSlicesAreAccountLists() {
    #expect(SidebarItem.tag("x").isAccountList)
    #expect(!SidebarItem.health.isAccountList)
    #expect(!SidebarItem.deleted.isAccountList)
  }
}
