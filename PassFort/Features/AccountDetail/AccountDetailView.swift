import Foundation
import PassFortVault
import SwiftUI

/// One account, **decrypted on demand**: `.task(id:)` runs a single
/// `repo.account(id:)` (one `pf_open`) when the selection changes, `.onDisappear`
/// drops the plaintext. Scoped to this view's lifetime — the §3.4 mitigation.
struct AccountDetailView: View {
  @Environment(AppModel.self) private var model
  let accountID: UUID

  @State private var load: AppModel.AccountLoad?
  @State private var revealHistory = false
  @State private var editing = false
  @State private var togglingFavorite = false

  var body: some View {
    Group {
      switch load {
      case .loaded(let account) where account.isDeleted:
        ContentUnavailableView {
          Label("“\(account.payload.title)” is deleted", systemImage: "trash")
        } description: {
          Text("It stays in Recently Deleted until you empty it.")
        } actions: {
          Button("Restore") { Task { _ = await model.restoreAccount(id: account.id) } }
        }
      case .loaded(let account):
        content(account)
      case .missing:
        ContentUnavailableView("Account not found", systemImage: "questionmark.folder")
      case .failed(let message):
        ContentUnavailableView(
          "Can't open this account", systemImage: "exclamationmark.lock",
          description: Text(message))
      case nil:
        ProgressView()
      }
    }
    .task(id: accountID) {
      revealHistory = false
      await reload()
    }
    .onChange(of: model.writeCounter) {
      Task { await reload() }  // an edit / delete happened — re-decrypt
    }
    .onDisappear {
      load = nil
      revealHistory = false
    }
  }

  private func reload() async {
    load = nil
    load = await model.loadAccount(id: accountID)
  }

  @ViewBuilder
  private func content(_ account: Account) -> some View {
    let payload = account.payload
    Form {
      Section {
        copyableRow("Username", payload.username)
        if let password = payload.password, !password.isEmpty {
          ConcealedRow(label: "Password", value: password, showsStrength: true)
        }
        if let totp = payload.totp { OneTimeCodeRow(config: totp) }
        copyableRow("Email", payload.email)
        concealedRow("PIN", payload.pin)
        concealedRow("Memorable word", payload.memorableWord)
        row("Notes", payload.notes)
      } header: {
        header(payload)
      }

      if !payload.securityQuestions.isEmpty {
        Section("Security questions") {
          ForEach(Array(payload.securityQuestions.enumerated()), id: \.offset) { _, item in
            ConcealedRow(
              label: item.question.isEmpty ? "Answer" : item.question, value: item.answer)
          }
        }
      }

      if !payload.recoveryCodes.isEmpty {
        Section("Recovery codes") {
          ForEach(Array(payload.recoveryCodes.enumerated()), id: \.offset) { index, code in
            ConcealedRow(label: "Code \(index + 1)", value: code)
          }
        }
      }

      if !payload.customFields.isEmpty {
        Section("Custom fields") {
          ForEach(payload.customFields) { field in
            if field.concealed || field.kind == .secret {
              ConcealedRow(label: field.label, value: field.value)
            } else {
              copyableRow(field.label, field.value)
            }
          }
        }
      }

      if !payload.urls.isEmpty {
        Section("URLs") {
          ForEach(payload.urls, id: \.self) { url in
            Link(destination: url) {
              Label(url.absoluteString, systemImage: "safari")
            }
            .foregroundStyle(Palette.primary)
            .lineLimit(1)
            .truncationMode(.middle)
          }
        }
      }

      Section("Details") {
        LabeledContent("Category") {
          Text(payload.category.singularName).foregroundStyle(
            Palette.color(payload.category.family))
        }
        if payload.favorite { LabeledContent("Favorite", value: "Yes") }
        if !payload.tags.isEmpty {
          LabeledContent("Tags") {
            HStack(spacing: 6) {
              ForEach(payload.tags, id: \.self) { tag in
                Text(tag)
                  .font(.caption)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 2)
                  .background(.quaternary, in: Capsule())
              }
            }
          }
        }
        if let expiresAt = payload.expiresAt {
          LabeledContent("Expires") {
            Text(expiresAt.formatted(date: .abbreviated, time: .omitted))
              .foregroundStyle(expiresAt < .now ? Palette.danger : Color.primary)
          }
        }
        LabeledContent("Created", value: stamp(payload.createdAt))
        LabeledContent("Updated", value: stamp(account.lastUpdated))
        if let changed = payload.passwordChangedAt {
          LabeledContent("Password changed", value: stamp(changed))
        }
      }

      historySection(payload)
      statsSection(account)
    }
    .formStyle(.grouped)
    .id(account.id)  // a fresh ConcealedRow identity per account: switching re-conceals
    .navigationTitle(payload.title)
    .toolbar {
      Button {
        Task { await toggleFavorite(account) }
      } label: {
        Label(
          payload.favorite ? "Remove Favorite" : "Mark as Favorite",
          systemImage: payload.favorite ? "star.fill" : "star"
        )
        .foregroundStyle(payload.favorite ? Palette.favorite : Color.primary)
      }
      .disabled(togglingFavorite)
      .help(payload.favorite ? "Remove from Favorites" : "Add to Favorites")

      Button("Edit") { editing = true }
    }
    .sheet(isPresented: $editing) {
      AccountFormView(mode: .edit(account))
    }
  }

  /// The large category tile, the title, and the host · category line above the first section.
  private func header(_ payload: AccountPayload) -> some View {
    HStack(spacing: 14) {
      CategoryTile(title: payload.title, category: payload.category, size: 52)
      VStack(alignment: .leading, spacing: 3) {
        Text(payload.title)
          .font(.title2.weight(.semibold))
          .foregroundStyle(.primary)
          .textSelection(.enabled)
        HStack(spacing: 6) {
          if let host = payload.urls.first?.host() {
            Text(host)
            Text("·").accessibilityHidden(true)
          }
          Text(payload.category.singularName)
            .foregroundStyle(Palette.color(payload.category.family))
        }
        .font(.callout)
        .foregroundStyle(.secondary)
      }
    }
    .textCase(nil)
    .padding(.bottom, 8)
  }

  private func toggleFavorite(_ account: Account) async {
    guard !togglingFavorite else { return }
    togglingFavorite = true
    defer { togglingFavorite = false }
    var payload = account.payload
    payload.favorite.toggle()
    _ = await model.updateAccount(id: account.id, to: payload)
  }

  @ViewBuilder
  private func concealedRow(_ label: String, _ value: String?) -> some View {
    if let value, !value.isEmpty {
      ConcealedRow(label: label, value: value)
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
              ConcealedRow(
                label: entry.replacedAt.formatted(date: .abbreviated, time: .omitted),
                value: entry.password)
            }
          }
        }
      }
    }
  }

  /// Nonce(24) ‖ tag(16) -- the AEAD envelope overhead on every sealed record
  /// (`record_crypto.cpp`'s `kNonceLen`/`kTagLen`), used to back out the
  /// plaintext size below.
  private static let aeadOverhead = 24 + 16

  @ViewBuilder
  private func statsSection(_ account: Account) -> some View {
    Section("Stats") {
      LabeledContent("Sealed size", value: byteCount(account.sealedSize))
      LabeledContent(
        "Plaintext size", value: byteCount(max(0, account.sealedSize - Self.aeadOverhead)))
      LabeledContent("Cipher", value: "XChaCha20-Poly1305")
      LabeledContent("Record version", value: "\(account.version)")
      LabeledContent("Schema version", value: "\(account.schemaVersion)")
      LabeledContent(
        "Sync clock", value: "#\(account.updatedAt.counter) · device \(shortDeviceID(account))")
    }
  }

  private func byteCount(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  private func shortDeviceID(_ account: Account) -> String {
    String(account.updatedAt.deviceID.uuidString.prefix(8))
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
          IconButton("Copy \(label.lowercased())", systemImage: "doc.on.doc") {
            Pasteboard.copy(value)
          }
        }
      }
    }
  }

  private func stamp(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}
