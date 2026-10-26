import Foundation
import PassFortVault
import SwiftUI
import UniformTypeIdentifiers

/// One form, two modes, bound to a **draft copy** of the payload, laid out like the detail view:
/// the tile-and-title header, the sign-in fields, website and tags, notes, then the optional
/// sections. A new account starts with the essentials and adds the rest from the Add Field menu
/// (`OptionalField`); an edited one shows whatever it already holds. Save goes through
/// `AppModel`, which does the `VaultRepository` write (one transaction, §8.2) and refreshes the
/// index.
struct AccountFormView: View {
  enum Mode {
    case create
    case edit(Account)
  }

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  /// The vault window's toast, for Delete's Undo. Optional so previews keep working.
  @Environment(ToastCenter.self) private var toasts: ToastCenter?

  let mode: Mode
  /// The payload the form opened with, to tell whether Cancel would throw anything away.
  private let original: AccountPayload
  @State private var draft: AccountPayload
  @State private var shown: Set<OptionalField>
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
  @State private var expiry: Date
  @State private var saving = false
  @State private var error: String?
  @State private var confirmingDiscard = false

  init(mode: Mode) {
    self.mode = mode
    let payload: AccountPayload
    switch mode {
    case .create: payload = AccountPayload(title: "")
    case .edit(let account): payload = account.payload
    }
    original = payload
    _draft = State(initialValue: payload)
    _shown = State(initialValue: OptionalField.shown(in: payload))
    _urlsText = State(initialValue: payload.urls.map(\.absoluteString).joined(separator: "\n"))
    _tagsText = State(initialValue: payload.tags.joined(separator: ", "))
    _totpText = State(initialValue: payload.totp?.otpauthURI ?? "")
    _questions = State(initialValue: payload.securityQuestions.map { EditableQuestion($0) })
    _recoveryCodesText = State(initialValue: payload.recoveryCodes.joined(separator: "\n"))
    _expiry = State(
      initialValue: payload.expiresAt ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)
        ?? .now)
  }

  private var isEditing: Bool { if case .edit = mode { return true } else { return false } }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField("Username", text: optional($draft.username), prompt: Text("Sign-in name"))
          PasswordEditor(password: optional($draft.password))
          if shown.contains(.oneTimeCode) { oneTimeCodeRow }
          TextField("Email", text: optional($draft.email), prompt: Text("Email address"))
          if shown.contains(.pin) {
            removableRow(.pin) { SecureField("PIN", text: optional($draft.pin)) }
          }
          if shown.contains(.memorableWord) {
            removableRow(.memorableWord) {
              SecureField("Memorable word", text: optional($draft.memorableWord))
            }
          }
        } header: {
          AccountFormHeader(
            title: $draft.title, category: $draft.category, favorite: $draft.favorite,
            isNew: !isEditing)
        }

        Section {
          TextField(
            "Website", text: $urlsText, prompt: Text(verbatim: "https://… one per line"),
            axis: .vertical)
          TextField("Tags", text: $tagsText, prompt: Text("Comma-separated"))
          if shown.contains(.expiry) {
            removableRow(.expiry) {
              DatePicker("Expires", selection: $expiry, displayedComponents: .date)
            }
          }
        }

        Section {
          TextField(
            "Notes", text: optional($draft.notes), prompt: Text("Anything else worth keeping"),
            axis: .vertical
          )
          .lineLimit(2...10)
        }

        if shown.contains(.securityQuestions) {
          SecurityQuestionsEditor(questions: $questions)
        }
        if shown.contains(.recoveryCodes) {
          Section("Recovery codes") {
            DisclosureGroup(
              "\(Self.parseLines(recoveryCodesText).count) codes", isExpanded: $showingRecoveryCodes
            ) {
              TextField("One per line", text: $recoveryCodesText, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(3...12)
            }
          }
        }
        if shown.contains(.customFields) {
          CustomFieldsEditor(fields: $draft.customFields)
        }

        Section {
          addFieldMenu
        } footer: {
          if let error {
            Label(error, systemImage: "xmark.octagon").foregroundStyle(Palette.danger)
          }
        }
      }
      .formStyle(.grouped)

      Divider()
      HStack {
        if isEditing {
          Button("Delete", role: .destructive) { Task { await delete() } }
        }
        Spacer()
        Button("Cancel") { if hasChanges { confirmingDiscard = true } else { dismiss() } }
          .keyboardShortcut(.cancelAction)
        Button(isEditing ? "Save" : "Add Account") { Task { await save() } }
          .keyboardShortcut(.defaultAction)
          .disabled(saving || draft.title.isEmpty)
      }
      .padding()
    }
    .frame(width: 500, height: 620)
    .interactiveDismissDisabled(hasChanges)
    .disabled(saving)
    .overlay { if saving { ProgressView() } }
    .confirmationDialog(
      isEditing ? "Discard your changes?" : "Discard this account?",
      isPresented: $confirmingDiscard, titleVisibility: .visible
    ) {
      Button(isEditing ? "Discard Changes" : "Discard Account", role: .destructive) { dismiss() }
      Button("Keep Editing", role: .cancel) {}
    } message: {
      Text(
        isEditing
          ? "Your edits to “\(original.title)” aren't saved." : "Nothing you typed is saved.")
    }
    .fileImporter(isPresented: $importingQR, allowedContentTypes: [.image]) { result in
      readQR(result)
    }
  }

  // MARK: - Optional fields

  private var addFieldMenu: some View {
    Menu {
      ForEach(OptionalField.addable(given: shown), id: \.self) { field in
        Button(field.title, systemImage: field.systemImage) { add(field) }
      }
    } label: {
      Label("Add Field", systemImage: "plus")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
  }

  private func add(_ field: OptionalField) {
    shown.insert(field)
    switch field {
    case .securityQuestions: questions.append(EditableQuestion())
    case .customFields: draft.customFields.append(CustomField(label: "", value: ""))
    case .recoveryCodes: showingRecoveryCodes = true
    case .oneTimeCode, .pin, .memorableWord, .expiry: break
    }
  }

  /// A single optional field with a remove button that clears it and takes it off screen.
  private func removableRow<Content: View>(
    _ field: OptionalField, @ViewBuilder content: () -> Content
  ) -> some View {
    HStack {
      content()
      Button("Remove \(field.title)", systemImage: "minus.circle") { remove(field) }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Remove \(field.title)")
    }
  }

  private func remove(_ field: OptionalField) {
    shown.remove(field)
    switch field {
    case .oneTimeCode: totpText = ""
    case .pin: draft.pin = nil
    case .memorableWord: draft.memorableWord = nil
    case .expiry, .securityQuestions, .recoveryCodes, .customFields: break
    }
  }

  /// The one-time-code field, the QR button, and what the field currently parses to.
  private var oneTimeCodeRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      removableRow(.oneTimeCode) {
        SecureField(
          "One-time code", text: $totpText, prompt: Text(verbatim: "otpauth:// link or secret"))
        Button("From QR Image…") { importingQR = true }
      }
      totpStatus.font(.caption)
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
  private var totpStatus: some View {
    switch parsedTOTP {
    case .success(nil):
      EmptyView()
    case .success(let config?):
      let name = [config.issuer, config.label].compactMap { $0 }.joined(separator: " · ")
      Label(
        name.isEmpty ? "Valid one-time code secret" : name,
        systemImage: "checkmark.circle"
      )
      .foregroundStyle(Palette.success)
    case .failure(let error):
      Label(Self.describe(error), systemImage: "exclamationmark.triangle")
        .foregroundStyle(Palette.warning)
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

  /// The payload as the form stands -- what Save writes -- or why it can't be one yet.
  private func edited() -> Result<AccountPayload, FormProblem> {
    var payload = draft
    payload.urls = Self.parseURLs(urlsText)
    payload.tags = Self.parseTags(tagsText)
    payload.recoveryCodes = Self.parseLines(recoveryCodesText)
    payload.securityQuestions = questions.compactMap(\.model)
    payload.customFields = CustomFieldsEditor.cleaned(payload.customFields)
    payload.expiresAt = shown.contains(.expiry) ? expiry : nil
    switch parsedTOTP {
    case .success(let config):
      // Unchanged text keeps the stored config byte-for-byte (no spurious "totp" revision).
      if totpText != payload.totp?.otpauthURI { payload.totp = config }
    case .failure(let failure):
      return .failure(FormProblem(message: "One-time code: " + Self.describe(failure)))
    }
    return .success(payload)
  }

  /// Whether Cancel would throw something away. A one-time code that doesn't parse counts: it
  /// was typed.
  private var hasChanges: Bool {
    guard case .success(let payload) = edited() else { return true }
    return payload != original
  }

  private struct FormProblem: Error {
    let message: String
  }

  private func save() async {
    saving = true
    defer { saving = false }
    error = nil

    let payload: AccountPayload
    switch edited() {
    case .success(let built): payload = built
    case .failure(let problem):
      error = problem.message
      return
    }

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

  /// No confirmation, as in the list: the account goes to Recently Deleted and the vault window's
  /// toast offers Undo. Unsaved edits go with it.
  private func delete() async {
    guard case .edit(let account) = mode else { return }
    saving = true
    defer { saving = false }
    if let failure = await model.deleteAccount(id: account.id) {
      error = failure.message
      return
    }
    dismiss()
    let model = self.model
    toasts?.showDeleted(original.title) {
      Task { _ = await model.restoreAccount(id: account.id) }
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
