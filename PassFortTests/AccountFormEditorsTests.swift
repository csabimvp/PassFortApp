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
}
