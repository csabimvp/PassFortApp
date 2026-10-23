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

// MARK: - Optional fields

/// The fields the form keeps off screen until they are wanted. A new account starts with the
/// essentials (title, username, password, email, website, tags, notes) and adds these from the
/// Add Field menu; an edited account shows each one that already holds something.
enum OptionalField: CaseIterable, Hashable {
  case oneTimeCode, pin, memorableWord, expiry, securityQuestions, recoveryCodes, customFields

  var title: String {
    switch self {
    case .oneTimeCode: "One-Time Code"
    case .pin: "PIN"
    case .memorableWord: "Memorable Word"
    case .expiry: "Expiry Date"
    case .securityQuestions: "Security Question"
    case .recoveryCodes: "Recovery Codes"
    case .customFields: "Custom Field"
    }
  }

  var systemImage: String {
    switch self {
    case .oneTimeCode: "clock.badge.checkmark"
    case .pin: "circle.grid.3x3"
    case .memorableWord: "text.quote"
    case .expiry: "calendar"
    case .securityQuestions: "questionmark.bubble"
    case .recoveryCodes: "lifepreserver"
    case .customFields: "list.bullet.rectangle"
    }
  }

  /// Rows that can be added more than once stay in the menu after the first.
  var repeatable: Bool { self == .securityQuestions || self == .customFields }

  /// The optional fields `payload` already fills, shown when the form opens.
  static func shown(in payload: AccountPayload) -> Set<OptionalField> {
    var shown: Set<OptionalField> = []
    if payload.totp != nil { shown.insert(.oneTimeCode) }
    if !(payload.pin ?? "").isEmpty { shown.insert(.pin) }
    if !(payload.memorableWord ?? "").isEmpty { shown.insert(.memorableWord) }
    if payload.expiresAt != nil { shown.insert(.expiry) }
    if !payload.securityQuestions.isEmpty { shown.insert(.securityQuestions) }
    if !payload.recoveryCodes.isEmpty { shown.insert(.recoveryCodes) }
    if !payload.customFields.isEmpty { shown.insert(.customFields) }
    return shown
  }

  /// What the Add Field menu offers: every field not on screen, plus the repeatable ones.
  static func addable(given shown: Set<OptionalField>) -> [OptionalField] {
    allCases.filter { !shown.contains($0) || $0.repeatable }
  }
}

// MARK: - Header

/// The form's version of the detail view's header: the category tile, updating as the title and
/// category change, a large title field, the category as a menu in its family colour, and the
/// favorite star.
struct AccountFormHeader: View {
  @Binding var title: String
  @Binding var category: AccountCategory
  @Binding var favorite: Bool
  let isNew: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      CategoryTile(title: title, category: category, size: 52)
      VStack(alignment: .leading, spacing: 4) {
        TextField("Title", text: $title, prompt: Text(isNew ? "New account" : "Title"))
          .textFieldStyle(.plain)
          .font(.title2.weight(.semibold))
          .labelsHidden()
        Menu {
          Picker("Category", selection: $category) {
            ForEach(AccountCategory.allCases, id: \.self) { category in
              Label(category.singularName, systemImage: category.symbol).tag(category)
            }
          }
          .pickerStyle(.inline)
          .labelsHidden()
        } label: {
          Text(category.singularName)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .tint(Palette.color(category.family))
        .foregroundStyle(Palette.color(category.family))
        .fixedSize()
        .help("Category")
      }
      Spacer(minLength: 0)
      Button(
        favorite ? "Remove from Favorites" : "Add to Favorites",
        systemImage: favorite ? "star.fill" : "star"
      ) {
        favorite.toggle()
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .font(.title3)
      .foregroundStyle(favorite ? AnyShapeStyle(Palette.favorite) : AnyShapeStyle(.secondary))
      .help(favorite ? "Remove from Favorites" : "Add to Favorites")
    }
    .textCase(nil)
    .padding(.bottom, 8)
  }
}

// MARK: - Password

/// The password row: concealed until revealed, the generator in a popover on the wand, and the
/// strength meter under the field once there is something to rate.
struct PasswordEditor: View {
  @Binding var password: String

  @State private var revealed = false
  @State private var generating = false

  var body: some View {
    LabeledContent("Password") {
      VStack(alignment: .trailing, spacing: 6) {
        HStack(spacing: 6) {
          Group {
            if revealed {
              TextField("Password", text: $password, prompt: Text("Type or generate"))
                .font(.system(.body, design: .monospaced))
            } else {
              SecureField("Password", text: $password, prompt: Text("Type or generate"))
            }
          }
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          IconButton(
            revealed ? "Conceal password" : "Reveal password",
            systemImage: revealed ? "eye.slash" : "eye"
          ) {
            revealed.toggle()
          }
          IconButton("Generate password", systemImage: "wand.and.stars") { generating = true }
            .popover(isPresented: $generating, arrowEdge: .trailing) {
              PasswordGeneratorView { password = $0 }
            }
        }
        if !password.isEmpty {
          let level = StrengthLevel(password: password)
          HStack(spacing: 8) {
            Text(level.title)
              .font(.caption.weight(.semibold))
              .foregroundStyle(level.color)
            StrengthMeter(level: level, height: 4).frame(width: 120)
          }
        }
      }
    }
  }
}
