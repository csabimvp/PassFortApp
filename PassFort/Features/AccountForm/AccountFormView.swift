import Foundation
import PassFortVault
import SwiftUI

/// One form, two modes, bound to a **draft copy** of the payload. Save goes
/// through `AppModel`, which does the `VaultRepository` write (one transaction,
/// §8.2) and refreshes the index.
struct AccountFormView: View {
  enum Mode {
    case create
    case edit(Account)
  }

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let mode: Mode
  @State private var draft: AccountPayload
  @State private var urlsText: String
  @State private var tagsText: String
  @State private var saving = false
  @State private var error: String?
  @State private var confirmingDelete = false

  init(mode: Mode) {
    self.mode = mode
    let payload: AccountPayload
    switch mode {
    case .create: payload = AccountPayload(title: "")
    case .edit(let account): payload = account.payload
    }
    _draft = State(initialValue: payload)
    _urlsText = State(initialValue: payload.urls.map(\.absoluteString).joined(separator: "\n"))
    _tagsText = State(initialValue: payload.tags.joined(separator: ", "))
  }

  private var isEditing: Bool { if case .edit = mode { return true } else { return false } }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        TextField("Title", text: $draft.title)

        Section("Credential") {
          TextField("Username", text: optional($draft.username))
          HStack {
            SecureField("Password", text: optional($draft.password))
            Button("Generate") { draft.password = try? PasswordPolicy().generate() }
          }
          TextField("Email", text: optional($draft.email))
        }

        Section {
          TextField("URLs (one per line)", text: $urlsText, axis: .vertical)
          TextField("Notes", text: optional($draft.notes), axis: .vertical)
          TextField("Tags (comma-separated)", text: $tagsText)
          Picker("Category", selection: $draft.category) {
            ForEach(AccountCategory.allCases, id: \.self) { category in
              Text(category.rawValue).tag(category)
            }
          }
          Toggle("Favorite", isOn: $draft.favorite)
        }

        if let error {
          Label(error, systemImage: "xmark.octagon").foregroundStyle(.red)
        }
      }
      .formStyle(.grouped)

      Divider()
      HStack {
        if isEditing {
          Button("Delete", role: .destructive) { confirmingDelete = true }
        }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save") { Task { await save() } }
          .keyboardShortcut(.defaultAction)
          .disabled(saving || draft.title.isEmpty)
      }
      .padding()
    }
    .frame(width: 440, height: 520)
    .disabled(saving)
    .overlay { if saving { ProgressView() } }
    .confirmationDialog(
      "Delete this account?", isPresented: $confirmingDelete, titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) { Task { await delete() } }
    } message: {
      Text("It's tombstoned — recoverable until the vault is compacted (M5).")
    }
  }

  private func save() async {
    saving = true
    defer { saving = false }
    error = nil

    draft.urls = Self.parseURLs(urlsText)
    draft.tags = Self.parseTags(tagsText)

    let payload = draft
    let failure: AppError?
    switch mode {
    case .create:
      failure = await model.createAccount(payload)
    case .edit(let account):
      failure = await model.updateAccount(id: account.id, to: payload)
    }

    if let failure {
      error = failure.message
    } else {
      dismiss()
    }
  }

  private func delete() async {
    guard case .edit(let account) = mode else { return }
    saving = true
    defer { saving = false }
    if let failure = await model.deleteAccount(id: account.id) {
      error = failure.message
    } else {
      dismiss()
    }
  }

  /// A non-optional `String` binding over an optional field — empty string ↔ nil.
  private func optional(_ source: Binding<String?>) -> Binding<String> {
    Binding(
      get: { source.wrappedValue ?? "" },
      set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
  }

  private static func parseURLs(_ text: String) -> [URL] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
      URL(string: line.trimmingCharacters(in: .whitespaces))
    }
  }

  private static func parseTags(_ text: String) -> [String] {
    text.split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}
