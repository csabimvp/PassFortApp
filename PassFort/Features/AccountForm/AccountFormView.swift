import Foundation
import PassFortVault
import SwiftUI
import UniformTypeIdentifiers

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
  /// The one-time-code field: an `otpauth://` URI or a Base32 secret, parsed on save.
  @State private var totpText: String
  @State private var importingQR = false
  @State private var questions: [EditableQuestion]
  /// Recovery codes, one per line. Behind a disclosure so a dozen live secrets aren't on screen
  /// the moment the form opens.
  @State private var recoveryCodesText: String
  @State private var showingRecoveryCodes = false
  @State private var hasExpiry: Bool
  @State private var expiry: Date
  @State private var saving = false
  @State private var error: String?
  @State private var confirmingDelete = false
  @State private var showingGenerator = false

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
    _totpText = State(initialValue: payload.totp?.otpauthURI ?? "")
    _questions = State(initialValue: payload.securityQuestions.map(EditableQuestion.init))
    _recoveryCodesText = State(initialValue: payload.recoveryCodes.joined(separator: "\n"))
    _hasExpiry = State(initialValue: payload.expiresAt != nil)
    _expiry = State(
      initialValue: payload.expiresAt ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)
        ?? .now)
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
            Button("Generate…") { showingGenerator = true }
          }
          TextField("Email", text: optional($draft.email))
          SecureField("PIN", text: optional($draft.pin))
          SecureField("Memorable word", text: optional($draft.memorableWord))
        }

        Section {
          HStack {
            SecureField("One-time code (otpauth:// link or secret)", text: $totpText)
            Button("From QR Image…") { importingQR = true }
          }
        } footer: {
          totpFooter
        }

        Section {
          DisclosureGroup(
            "Recovery codes (\(Self.parseLines(recoveryCodesText).count))",
            isExpanded: $showingRecoveryCodes
          ) {
            TextField("One per line", text: $recoveryCodesText, axis: .vertical)
              .font(.system(.body, design: .monospaced))
              .lineLimit(3...12)
          }
        }

        SecurityQuestionsEditor(questions: $questions)
        CustomFieldsEditor(fields: $draft.customFields)

        Section {
          TextField("URLs (one per line)", text: $urlsText, axis: .vertical)
          TextField("Notes", text: optional($draft.notes), axis: .vertical)
          TextField("Tags (comma-separated)", text: $tagsText)
          Picker("Category", selection: $draft.category) {
            ForEach(AccountCategory.allCases, id: \.self) { category in
              Text(category.singularName).tag(category)
            }
          }
          Toggle("Favorite", isOn: $draft.favorite)
          Toggle("Expires", isOn: $hasExpiry)
          if hasExpiry {
            DatePicker("Expiry date", selection: $expiry, displayedComponents: .date)
          }
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
    .frame(width: 480, height: 640)
    .disabled(saving)
    .overlay { if saving { ProgressView() } }
    .confirmationDialog(
      "Delete this account?", isPresented: $confirmingDelete, titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) { Task { await delete() } }
    } message: {
      Text("It's tombstoned — recoverable until the vault is compacted (M5).")
    }
    .sheet(isPresented: $showingGenerator) {
      PasswordGeneratorView { draft.password = $0 }
    }
    .fileImporter(isPresented: $importingQR, allowedContentTypes: [.image]) { result in
      readQR(result)
    }
  }

  // MARK: - One-time code

  /// What the one-time-code field currently means: nothing, a usable config, or why not.
  private var parsedTOTP: Result<TOTPConfig?, OneTimeCodeError> {
    let text = totpText.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return .success(nil) }
    do {
      return .success(try TOTPConfig(parsing: text))
    } catch let error as OneTimeCodeError {
      return .failure(error)
    } catch {
      return .failure(.unrecognized)
    }
  }

  @ViewBuilder
  private var totpFooter: some View {
    switch parsedTOTP {
    case .success(nil):
      EmptyView()
    case .success(let config?):
      let name = [config.issuer, config.label].compactMap { $0 }.joined(separator: " · ")
      Label(
        name.isEmpty ? "Valid one-time code secret" : name,
        systemImage: "checkmark.circle"
      )
      .foregroundStyle(.green)
    case .failure(let error):
      Label(Self.describe(error), systemImage: "exclamationmark.triangle")
        .foregroundStyle(.orange)
    }
  }

  private func readQR(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    if let uri = QRCodeReader.otpauthURI(inImageAt: url) {
      totpText = uri
      error = nil
    } else {
      error = "No authenticator QR code found in that image."
    }
  }

  static func describe(_ error: OneTimeCodeError) -> String {
    switch error {
    case .unrecognized: "Not an otpauth:// link or a Base32 secret."
    case .counterBasedNotSupported: "Counter-based (HOTP) codes aren't supported."
    case .missingSecret: "The link has no secret."
    case .badSecret: "The secret isn't valid Base32."
    case .unsupportedAlgorithm(let name): "Unsupported algorithm \(name)."
    case .badDigits: "Codes must be 6 to 10 digits."
    case .badPeriod: "The period must be a positive number of seconds."
    }
  }

  private func save() async {
    saving = true
    defer { saving = false }
    error = nil

    draft.urls = Self.parseURLs(urlsText)
    draft.tags = Self.parseTags(tagsText)
    draft.recoveryCodes = Self.parseLines(recoveryCodesText)
    draft.securityQuestions = questions.compactMap(\.model)
    draft.customFields = CustomFieldsEditor.cleaned(draft.customFields)
    draft.expiresAt = hasExpiry ? expiry : nil
    switch parsedTOTP {
    case .success(let config):
      // Unchanged text keeps the stored config byte-for-byte (no spurious "totp" revision).
      if totpText != draft.totp?.otpauthURI { draft.totp = config }
    case .failure(let failure):
      error = "One-time code: " + Self.describe(failure)
      return
    }

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

  private static func parseLines(_ text: String) -> [String] {
    text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  private static func parseTags(_ text: String) -> [String] {
    text.split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}
