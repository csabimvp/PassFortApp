import Foundation
import PassFortVault
import SwiftUI

// MARK: - Security questions

/// One security question as the form edits it. `SecurityQuestion` has no identity of its own, and
/// rows that come and go need one, so the form carries this and converts on save.
struct EditableQuestion: Identifiable, Equatable {
  let id = UUID()
  var question: String
  var answer: String
  var caseSensitive: Bool

  init(question: String = "", answer: String = "", caseSensitive: Bool = false) {
    self.question = question
    self.answer = answer
    self.caseSensitive = caseSensitive
  }

  init(_ source: SecurityQuestion) {
    self.init(
      question: source.question, answer: source.answer, caseSensitive: source.caseSensitive)
  }

  /// `nil` for a row left blank, so an untouched "Add Question" doesn't save an empty entry.
  var model: SecurityQuestion? {
    let trimmed = question.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty || !answer.isEmpty else { return nil }
    return SecurityQuestion(question: trimmed, answer: answer, caseSensitive: caseSensitive)
  }
}

/// Security questions: the question in the clear, the answer concealed — it is the secret.
struct SecurityQuestionsEditor: View {
  @Binding var questions: [EditableQuestion]

  var body: some View {
    Section("Security questions") {
      ForEach($questions) { $row in
        VStack(alignment: .leading) {
          HStack {
            TextField("Question", text: $row.question)
            Button("Remove question", systemImage: "minus.circle") {
              questions.removeAll { $0.id == row.id }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
          }
          SecureField("Answer", text: $row.answer)
          Toggle("Case-sensitive answer", isOn: $row.caseSensitive)
            .font(.caption)
        }
      }
      Button("Add Question", systemImage: "plus") { questions.append(EditableQuestion()) }
        .buttonStyle(.borderless)
    }
  }
}

// MARK: - Custom fields

/// Free-form label/value pairs (§7.2's escape hatch). A concealed field edits in a `SecureField`
/// and shows as dots in the detail view.
struct CustomFieldsEditor: View {
  @Binding var fields: [CustomField]

  var body: some View {
    Section("Custom fields") {
      ForEach($fields) { $field in
        HStack {
          TextField("Label", text: $field.label)
            .frame(maxWidth: 120)
          if field.concealed {
            SecureField("Value", text: $field.value)
          } else {
            TextField("Value", text: $field.value)
          }
          Toggle(isOn: $field.concealed) {
            Label("Concealed", systemImage: field.concealed ? "eye.slash" : "eye")
          }
          .toggleStyle(.button)
          .labelStyle(.iconOnly)
          .help(field.concealed ? "Concealed — shown as dots" : "Shown in the clear")
          Button("Remove field", systemImage: "minus.circle") {
            fields.removeAll { $0.id == field.id }
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
        }
      }
      Button("Add Field", systemImage: "plus") {
        fields.append(CustomField(label: "", value: ""))
      }
      .buttonStyle(.borderless)
    }
  }

  /// Drop rows left entirely blank, so an untouched "Add Field" doesn't save an empty entry.
  static func cleaned(_ fields: [CustomField]) -> [CustomField] {
    fields.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty || !$0.value.isEmpty }
  }
}
