import Foundation
import PassFortVault
import Testing

@testable import PassFort

/// What the compare sheet lists: the fields that differ, and only those.
struct ConflictCompareTests {
  @Test func onlyDifferingFieldsAreListedAndSecretsAreConcealed() {
    let other = AccountPayload(
      title: "Email", username: "me", password: "old", notes: "same", tags: ["work"])
    var copy = other
    copy.password = "new"
    copy.tags = ["work", "home"]
    copy.conflictOf = UUID()
    copy.revisionHistory = [RevisionEntry(version: 1, at: .now, changed: ["conflict copy"])]

    let differences = FieldDifference.between(copy: copy, other: other)
    #expect(differences.map(\.label) == ["Password", "Tags"])
    #expect(differences.first?.concealed == true)
    #expect(differences.first?.copy == "new")
    #expect(differences.first?.other == "old")
    #expect(differences.last?.concealed == false)
  }

  @Test func againstAMissingVersionEveryFilledFieldDiffers() {
    let copy = AccountPayload(title: "Gone", username: "me")
    let differences = FieldDifference.between(copy: copy, other: nil)
    #expect(differences.map(\.label) == ["Title", "Category", "Username"])
    #expect(differences.allSatisfy { $0.other == nil })
  }

  @Test func anEmptyValueCountsAsAbsent() {
    let copy = AccountPayload(title: "X", notes: "")
    let other = AccountPayload(title: "X", notes: nil)
    #expect(FieldDifference.between(copy: copy, other: other).isEmpty)
  }
}
