import PassFortVault
import SwiftUI

/// One field that differs between a conflict copy and the version it was split from. Concealed
/// values stay masked until the sheet's reveal toggle is on.
struct FieldDifference: Equatable, Identifiable {
  let label: String
  /// The copy's value; `nil` when the copy doesn't have the field.
  let copy: String?
  /// The other version's; `nil` when it doesn't have the field (or is gone).
  let other: String?
  let concealed: Bool

  var id: String { label }

  /// Every field the user can see that differs, in the detail view's order. Bookkeeping (history,
  /// dates, audit results, `conflictOf` itself) is left out: it differs by construction.
  static func between(copy: AccountPayload, other: AccountPayload?) -> [FieldDifference] {
    var differences: [FieldDifference] = []
    func compare(_ label: String, concealed: Bool = false, _ value: (AccountPayload) -> String?) {
      let mine = value(copy).flatMap { $0.isEmpty ? nil : $0 }
      let theirs = other.flatMap(value).flatMap { $0.isEmpty ? nil : $0 }
      if mine != theirs {
        differences.append(
          FieldDifference(label: label, copy: mine, other: theirs, concealed: concealed))
      }
    }
    func list(_ values: [String]) -> String? {
      values.isEmpty ? nil : values.joined(separator: "\n")
    }

    compare("Title") { $0.title }
    compare("Category") { $0.category.singularName }
    compare("Username") { $0.username }
    compare("Password", concealed: true) { $0.password }
    compare("One-time code", concealed: true) { payload in
      payload.totp.map { $0.secret.base64EncodedString() }
    }
    compare("Email") { $0.email }
    compare("PIN", concealed: true) { $0.pin }
    compare("Memorable word", concealed: true) { $0.memorableWord }
    compare("Websites") { list($0.urls.map(\.absoluteString)) }
    compare("Tags") { list($0.tags) }
    compare("Expires") { $0.expiresAt?.formatted(date: .abbreviated, time: .omitted) }
    compare("Notes") { $0.notes }
    compare("Security questions", concealed: true) { payload in
      list(payload.securityQuestions.map { "\($0.question): \($0.answer)" })
    }
    compare("Recovery codes", concealed: true) { list($0.recoveryCodes) }
    let labels = Set(copy.customFields.map(\.label) + (other?.customFields.map(\.label) ?? []))
    for label in labels.sorted() {
      let secret =
        (copy.customFields + (other?.customFields ?? [])).contains {
          $0.label == label && ($0.concealed || $0.kind == .secret)
        }
      compare(label, concealed: secret) { payload in
        payload.customFields.first { $0.label == label }?.value
      }
    }
    compare("Favorite") { $0.favorite ? "Yes" : nil }
    return differences
  }
}

/// The two versions of a conflicted account side by side (`m5-sync.md` A.11) -- only the fields
/// that differ. Both are decrypted while the sheet is up and dropped when it closes.
struct ConflictCompareView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let copy: Account

  @State private var other: AppModel.AccountLoad?
  @State private var reveal = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Compare versions").font(.title3).bold()
      content
      HStack {
        Toggle("Show concealed values", isOn: $reveal)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 620)
    .frame(minHeight: 280)
    .task {
      if let id = copy.payload.conflictOf {
        other = await model.loadAccount(id: id)
      } else {
        other = .missing
      }
    }
    .onDisappear {
      other = nil
      reveal = false
    }
  }

  @ViewBuilder
  private var content: some View {
    switch other {
    case nil:
      ProgressView().frame(maxWidth: .infinity)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.lock").foregroundStyle(Palette.danger)
    case .missing, .loaded:
      let otherAccount: Account? = if case .loaded(let account) = other { account } else { nil }
      let differences = FieldDifference.between(copy: copy.payload, other: otherAccount?.payload)
      if differences.isEmpty {
        Text("The two versions hold the same values.").foregroundStyle(.secondary)
      } else {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 10) {
          GridRow {
            Text("")
            Text("This copy").font(.headline)
            Text(otherTitle(otherAccount)).font(.headline)
          }
          Divider().gridCellUnsizedAxes(.horizontal)
          ForEach(differences) { difference in
            GridRow {
              Text(difference.label).foregroundStyle(.secondary)
              value(difference.copy, concealed: difference.concealed)
              value(difference.other, concealed: difference.concealed)
            }
          }
        }
      }
    }
  }

  private func otherTitle(_ account: Account?) -> String {
    guard let account else { return "Other version (gone)" }
    return account.isDeleted ? "Other version (deleted)" : "Other version"
  }

  private func value(_ text: String?, concealed: Bool) -> some View {
    Group {
      if let text {
        Text(concealed && !reveal ? String(repeating: "•", count: 10) : text)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("—").foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
