import Foundation
import PassFortVault
import SwiftUI

/// One account, **decrypted on demand**: `.task(id:)` runs a single
/// `repo.account(id:)` (one `pf_open`) when the selection changes, `.onDisappear`
/// drops the plaintext. Scoped to this view's lifetime — the §3.4 mitigation.
struct AccountDetailView: View {
  @Environment(AppModel.self) private var model
  let accountID: UUID

  @State private var account: Account?
  @State private var revealPassword = false
  @State private var revealHistory = false
  @State private var editing = false

  var body: some View {
    Group {
      if let account, account.isDeleted {
        ContentUnavailableView("Account deleted", systemImage: "trash")
      } else if let account {
        content(account)
      } else {
        ProgressView()
      }
    }
    .task(id: accountID) {
      revealPassword = false
      revealHistory = false
      await load()
    }
    .onChange(of: model.writeCounter) {
      Task { await load() }  // an edit / delete happened — re-decrypt
    }
    .onDisappear {
      account = nil
      revealPassword = false
    }
  }

  private func load() async {
    account = nil
    account = try? await model.repo?.account(id: accountID)
  }

  @ViewBuilder
  private func content(_ account: Account) -> some View {
    let payload = account.payload
    Form {
      Section {
        LabeledContent("Title", value: payload.title)
        copyableRow("Username", payload.username)
        passwordRow(payload.password)
        copyableRow("Email", payload.email)
        row("Notes", payload.notes)
      }

      if !payload.urls.isEmpty {
        Section("URLs") {
          ForEach(payload.urls, id: \.self) { url in
            Link(destination: url) {
              Label(url.absoluteString, systemImage: "safari")
            }
            .lineLimit(1)
            .truncationMode(.middle)
          }
        }
      }

      Section("Details") {
        LabeledContent("Category", value: payload.category.rawValue)
        if payload.favorite { LabeledContent("Favorite", value: "Yes") }
        if !payload.tags.isEmpty {
          LabeledContent("Tags", value: payload.tags.joined(separator: ", "))
        }
        row("PIN", payload.pin)
        row("Memorable word", payload.memorableWord)
        if payload.totp != nil { LabeledContent("TOTP", value: "configured") }
        if !payload.securityQuestions.isEmpty {
          LabeledContent("Security questions", value: "\(payload.securityQuestions.count)")
        }
        LabeledContent("Created", value: stamp(payload.createdAt))
        LabeledContent("Updated", value: stamp(account.lastUpdated))
        if let changed = payload.passwordChangedAt {
          LabeledContent("Password changed", value: stamp(changed))
        }
      }

      historySection(payload)
    }
    .formStyle(.grouped)
    .navigationTitle(payload.title)
    .toolbar {
      Button("Edit") { editing = true }
    }
    .sheet(isPresented: $editing) {
      AccountFormView(mode: .edit(account))
    }
  }

  @ViewBuilder
  private func passwordRow(_ password: String?) -> some View {
    if let password {
      LabeledContent("Password") {
        HStack {
          Text(revealPassword ? password : String(repeating: "•", count: 12))
            .font(.system(.body, design: .monospaced))
          Spacer()
          Button(revealPassword ? "Hide" : "Reveal") { revealPassword.toggle() }
          Button("Copy") { Pasteboard.copyTransient(password) }
        }
      }
    }
  }

  @ViewBuilder
  private func historySection(_ payload: AccountPayload) -> some View {
    if !payload.revisionHistory.isEmpty || !payload.passwordHistory.isEmpty {
      Section("History") {
        ForEach(payload.revisionHistory, id: \.version) { entry in
          LabeledContent("v\(entry.version)") {
            VStack(alignment: .trailing) {
              Text(entry.changed.joined(separator: ", "))
              Text(stamp(entry.at)).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        if !payload.passwordHistory.isEmpty {
          DisclosureGroup(
            "Previous passwords (\(payload.passwordHistory.count))", isExpanded: $revealHistory
          ) {
            ForEach(Array(payload.passwordHistory.enumerated()), id: \.offset) { _, entry in
              LabeledContent(
                entry.replacedAt.formatted(date: .abbreviated, time: .omitted),
                value: entry.password)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func row(_ label: String, _ value: String?) -> some View {
    if let value, !value.isEmpty {
      LabeledContent(label, value: value)
    }
  }

  /// A row with a copy button — for the non-concealed identity fields.
  @ViewBuilder
  private func copyableRow(_ label: String, _ value: String?) -> some View {
    if let value, !value.isEmpty {
      LabeledContent(label) {
        HStack(spacing: 6) {
          Text(value).textSelection(.enabled)
          Button("Copy \(label.lowercased())", systemImage: "doc.on.doc") {
            Pasteboard.copy(value)
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
        }
      }
    }
  }

  private func stamp(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}
