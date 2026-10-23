import Foundation
import PassFortVault
import Testing

@testable import PassFort

/// The account form's row conversions. An unchanged form must save back exactly what it loaded,
/// or every Save would log a spurious revision (`VaultRepository` diffs the payload).
struct AccountFormEditorsTests {

  @Test func aQuestionRoundTripsUnchanged() {
    let stored = SecurityQuestion(question: "First pet?", answer: "Rex", caseSensitive: true)
    #expect(EditableQuestion(stored).model == stored)
  }

  @Test func aBlankQuestionRowIsDropped() {
    #expect(EditableQuestion().model == nil)
    #expect(EditableQuestion(question: "  ").model == nil)
  }

  @Test func aQuestionIsTrimmedButItsAnswerIsNot() {
    let row = EditableQuestion(question: "  Street? ", answer: " Elm ")
    #expect(row.model == SecurityQuestion(question: "Street?", answer: " Elm "))
  }

  @Test func blankCustomFieldsAreDroppedAndTheRestKept() {
    let kept = CustomField(label: "Account no.", value: "1234", concealed: true)
    let valueOnly = CustomField(label: "", value: "x")
    let blank = CustomField(label: " ", value: "")
    #expect(CustomFieldsEditor.cleaned([kept, blank, valueOnly]) == [kept, valueOnly])
  }

  // MARK: - Optional fields

  @Test func aNewAccountShowsNoOptionalField() {
    #expect(OptionalField.shown(in: AccountPayload(title: "")).isEmpty)
  }

  @Test func anEditedAccountShowsEachOptionalFieldItFills() throws {
    var payload = AccountPayload(title: "Bank")
    payload.pin = "1234"
    payload.memorableWord = ""  // empty counts as unset, as the form saves it
    payload.recoveryCodes = ["abcd-efgh"]
    payload.expiresAt = Date(timeIntervalSince1970: 0)
    payload.totp = try TOTPConfig(parsing: "JBSWY3DPEHPK3PXP")
    #expect(OptionalField.shown(in: payload) == [.pin, .recoveryCodes, .expiry, .oneTimeCode])
  }

  @Test func theMenuOffersHiddenFieldsAndTheRepeatableOnes() {
    #expect(OptionalField.addable(given: []) == OptionalField.allCases)
    let shown: Set<OptionalField> = [.pin, .securityQuestions, .customFields]
    let addable = OptionalField.addable(given: shown)
    #expect(!addable.contains(.pin))
    #expect(addable.contains(.securityQuestions))
    #expect(addable.contains(.customFields))
    #expect(addable.contains(.memorableWord))
  }
}
