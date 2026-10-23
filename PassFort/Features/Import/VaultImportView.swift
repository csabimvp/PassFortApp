import AppKit
import PassFortVault
import SwiftUI

/// Copy accounts out of another PassFort vault -- a dev vault into this one, say: pick its file,
/// unlock it with its own password or recovery key (it is opened read-only and not changed), tick
/// what to bring over (likely duplicates start unticked), import in one transaction. The plan is
/// plaintext, so it lives only as long as this sheet.
struct VaultImportView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  private enum Step {
    case choosing
    case unlocking(file: URL)
    case picking(ImportPlan, file: URL)
    case done(count: Int, file: URL)
  }

  @State private var step = Step.choosing
  @State private var secret = ""
  @State private var useRecoveryKey = false
  @State private var chosen: Set<Int> = []
  @State private var working = false
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Import from Another Vault").font(.title3).bold()
      switch step {
      case .choosing: choosing
      case .unlocking(let file): unlocking(file)
      case .picking(let plan, let file): picking(plan, file: file)
      case .done(let count, let file): done(count: count, file: file)
      }
      if let error {
        Label(error, systemImage: "xmark.octagon").foregroundStyle(Palette.danger)
      }
    }
    .padding(24)
    .frame(width: 480)
    .disabled(working)
    .onDisappear {  // drop the plaintext plan and the typed secret with the sheet
      step = .choosing
      secret = ""
    }
  }

  // MARK: - Steps

  private var choosing: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        "Pick another PassFort vault file, then unlock it with its own password. It's opened "
          + "read-only and isn't changed. Nothing is written here until you confirm."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Choose Vault…", action: pick).keyboardShortcut(.defaultAction)
      }
    }
  }

  private func unlocking(_ file: URL) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(file.path(percentEncoded: false)).font(.caption).foregroundStyle(.secondary)
        .lineLimit(1).truncationMode(.middle)
      Picker("Unlock with", selection: $useRecoveryKey) {
        Text("Password").tag(false)
        Text("Recovery Key").tag(true)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      Group {
        if useRecoveryKey {
          TextField("Recovery key, as written down", text: $secret)
            .font(.body.monospaced())
        } else {
          SecureField("That vault's password", text: $secret)
        }
      }
      .onSubmit { Task { await unlock(file) } }
      HStack {
        Button("Choose Another…", action: pick)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Unlock") { Task { await unlock(file) } }
          .keyboardShortcut(.defaultAction)
          .disabled(secret.isEmpty)
      }
    }
  }

  private func picking(_ plan: ImportPlan, file: URL) -> some View {
    let duplicates = plan.duplicates(of: model.summaries)
    return VStack(alignment: .leading, spacing: 10) {
      Text(file.lastPathComponent).font(.caption).foregroundStyle(.secondary)

      if plan.accounts.isEmpty {
        Text("That vault has no accounts to import.").foregroundStyle(.secondary)
      } else {
        List(plan.accounts.indices, id: \.self) { index in
          let payload = plan.accounts[index].payload
          Toggle(isOn: chosenBinding(index)) {
            HStack {
              Text(payload.title)
              if let username = payload.username ?? payload.email {
                Text(username).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if payload.totp != nil {
                Image(systemName: "clock").help("Has a one-time code")
              }
              if duplicates.contains(index) {
                Text("already here").font(.caption).foregroundStyle(Palette.warning)
                  .help("Same title or website and username as an account in this vault")
              }
            }
          }
        }
        .frame(height: 260)

        HStack {
          Button("Select All") { chosen = Set(plan.accounts.indices) }
          Button("Select None") { chosen = [] }
        }
        .buttonStyle(.link)
      }
      ForEach(plan.warnings, id: \.self) { warning in
        Text(warning.prefix(1).uppercased() + warning.dropFirst() + ".")
          .font(.caption).foregroundStyle(.secondary)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Import \(chosen.count) Account\(chosen.count == 1 ? "" : "s")") {
          let payloads = chosen.sorted().map { plan.accounts[$0].payload }
          Task { await runImport(payloads, file: file) }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(chosen.isEmpty)
      }
    }
  }

  private func done(count: Int, file: URL) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(
        "Imported \(count) account\(count == 1 ? "" : "s") from “\(file.lastPathComponent)”.",
        systemImage: "checkmark.circle"
      )
      .foregroundStyle(Palette.success)
      Text("That vault is unchanged; its accounts are still there too.")
        .foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
  }

  // MARK: - Actions

  private func chosenBinding(_ index: Int) -> Binding<Bool> {
    Binding(
      get: { chosen.contains(index) },
      set: { if $0 { chosen.insert(index) } else { chosen.remove(index) } })
  }

  private func pick() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose Vault"
    panel.message = "Choose the PassFort vault to import from."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    secret = ""
    error = nil
    step = .unlocking(file: url)
  }

  private func unlock(_ file: URL) async {
    guard !secret.isEmpty, !working else { return }
    let credential: VaultImport.Credential
    if useRecoveryKey {
      guard let key = try? RecoveryKey(grouped: secret) else {
        error = "That doesn't look like a recovery key."
        return
      }
      credential = .recoveryKey(key)
    } else {
      credential = .password(Data(secret.utf8))
    }

    working = true
    defer { working = false }
    switch await model.planVaultImport(from: file, unlockingWith: credential) {
    case .success(let plan):
      secret = ""
      error = nil
      chosen = Set(plan.accounts.indices).subtracting(plan.duplicates(of: model.summaries))
      step = .picking(plan, file: file)
    case .failure(.wrongPassword):
      error =
        useRecoveryKey ? "That recovery key doesn't open this vault." : "Wrong password."
    case .failure(let failure):
      error = failure.message
    }
  }

  private func runImport(_ payloads: [AccountPayload], file: URL) async {
    working = true
    defer { working = false }
    if let failure = await model.importAccounts(payloads) {
      error = failure.message
    } else {
      error = nil
      step = .done(count: payloads.count, file: file)
    }
  }
}

#Preview {
  VaultImportView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
