import Foundation
import PassFortVault
import Testing

@testable import passfort_cli

/// How an account reference -- a title, part of one, an id or an id prefix -- picks accounts,
/// and the short ids `list` prints for them.
@Suite struct AccountMatchTests {

  private static func row(_ id: String, _ title: String, username: String? = nil)
    -> AccountSummary
  {
    AccountSummary(
      id: UUID(uuidString: id) ?? UUID(), title: title, username: username, lastUpdated: .now)
  }

  private let personal = row("32E68EC2-821F-4E47-BFE4-FEA4935C2FD6", "GitHub personal")
  private let work = row("A72BC9FE-96DB-4A7B-B3B1-A40BA363EFD9", "GitHub work")
  private let git = row("A72B0000-0000-4000-8000-000000000000", "Git")
  private var pool: [AccountSummary] { [personal, work, git] }

  // MARK: Matching

  @Test func anExactTitleBeatsASubstring() {
    #expect(matchAccount("git", in: pool) == .one(git.id))
  }

  @Test func aUniqueSubstringMatches() {
    #expect(matchAccount("WORK", in: pool) == .one(work.id))
  }

  @Test func severalSubstringsAreAmbiguous() {
    #expect(matchAccount("hub", in: pool) == .several([personal, work]))
  }

  @Test func duplicateExactTitlesAreAmbiguous() {
    let twin = Self.row("00000000-0000-4000-8000-000000000001", "Git")
    #expect(matchAccount("Git", in: pool + [twin]) == .several([git, twin]))
  }

  @Test func anIDPrefixMatchesInEitherCase() {
    #expect(matchAccount("32e6", in: pool) == .one(personal.id))
    #expect(matchAccount("A72BC9", in: pool) == .one(work.id))
    #expect(matchAccount("a72b", in: pool) == .several([work, git]))
  }

  @Test func aShortHexWordIsATitleNotAnIDPrefix() {
    #expect(matchAccount("a7", in: pool) == .none)
    let cafe = Self.row("CAFE0000-0000-4000-8000-000000000000", "Bistro")
    #expect(matchAccount("caf", in: [cafe]) == .none)
    #expect(matchAccount("cafe", in: [cafe]) == .one(cafe.id))
  }

  @Test func aFullIDIsTakenAsIs() {
    let unknown = UUID()
    #expect(matchAccount(unknown.uuidString, in: pool) == .one(unknown))
  }

  @Test func nothingMatches() {
    #expect(matchAccount("bank", in: pool) == .none)
  }

  // MARK: Short ids

  @Test func shortIDsAreEightLowercaseCharacters() {
    let ids = shortIDs(pool.map(\.id))
    #expect(ids[personal.id] == "32e68ec2")
    #expect(ids[work.id] == "a72bc9fe")
    #expect(ids[git.id] == "a72b0000")
  }

  @Test func shortIDsWidenUntilTheyDiffer() {
    let a = UUID(uuidString: "12345678-AAAA-4000-8000-000000000000") ?? UUID()
    let b = UUID(uuidString: "12345678-ABBB-4000-8000-000000000000") ?? UUID()
    let ids = shortIDs([a, b])
    #expect(ids[a] == "12345678-aa")
    #expect(ids[b] == "12345678-ab")
  }

  // MARK: The picker

  @Test func theMenuNumbersEachAccountWithItsShortID() {
    let menu = AccountPicker.menu(
      [Self.row(personal.id.uuidString, "GitHub personal", username: "me"), work], for: "hub")
    let expected = [
      "\"hub\" matches 2 accounts:",
      "  1) GitHub personal  me  [32e68ec2]",
      "  2) GitHub work  [a72bc9fe]",
      "Which one? [1-2]: ",
    ].joined(separator: "\n")
    #expect(menu == expected)
  }
}
