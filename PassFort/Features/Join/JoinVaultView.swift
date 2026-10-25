import Foundation
import SwiftUI

/// Join a vault another device syncs (`m5-sync.md` A.11): the server, the vault id -- or one
/// pasted invite holding both -- and that vault's master password. PassFort fetches the vault's
/// header, unlocks it, builds this Mac's copy and downloads every account.
///
/// Two places: first run, beside Create (`.firstRun`), and Settings ▸ Vault, where the open vault
/// is set aside and kept, as Start a New Vault and Load Vault do (`.replacingVault`).
struct JoinVaultView: View {
  enum Mode {
    case firstRun
    case replacingVault
  }

  let mode: Mode

  @Environment(AppModel.self) private var model
  @Environment(BackupModel.self) private var backup: BackupModel?
  @Environment(\.dismiss) private var dismiss

  @State private var endpointText = SyncEndpoint.lastUsed?.absoluteString ?? ""
  @State private var vaultText = ""
  @State private var password = ""
  @State private var working = false
  @State private var error: AppError?
  /// Where the previous vault was kept, once the joined one is live (`.replacingVault`).
  @State private var keptAt: String?

  private var endpoint: URL? { SyncEndpoint.parse(endpointText) }
  private var vaultID: UUID? {
    UUID(uuidString: vaultText.trimmingCharacters(in: .whitespacesAndNewlines))
  }
  private var canSubmit: Bool { endpoint != nil && vaultID != nil && !password.isEmpty }

  var body: some View {
    Group {
      if let keptAt {
        done(keptAt)
      } else {
        form
      }
    }
    .textFieldStyle(.roundedBorder)
    .padding(24)
    .frame(width: 420)
  }

  // MARK: - Form

  private var form: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Join a synced vault").font(.title3).bold()

      Text(intro)
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      TextField("Server, or an invite link", text: $endpointText)
        .onChange(of: endpointText) { _, text in
          guard let invite = SyncInvite.parse(text) else { return }
          endpointText = invite.endpoint.absoluteString
          vaultText = invite.vaultID.uuidString.lowercased()
        }
      TextField("Vault ID", text: $vaultText)
        .font(.system(.body, design: .monospaced))
      SecureField("That vault's master password", text: $password)

      if let error {
        Label(error.message, systemImage: "xmark.octagon")
          .font(.callout).foregroundStyle(Palette.danger)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        if working {
          ProgressView().controlSize(.small)
          Text("Fetching and unlocking the vault…").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Join Vault", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(working || !canSubmit)
      }
    }
    .disabled(working)
  }

  private var intro: String {
    let common =
      "On the device that already syncs the vault, open Settings ▸ Sync ▸ Add a Device for "
      + "its server and vault ID. The server never learns the password."
    switch mode {
    case .firstRun:
      return common
    case .replacingVault:
      return common
        + " The open vault is set aside next to the new one and kept, never deleted, with its "
        + "own sync settings: load it again to switch back."
    }
  }

  private func done(_ keptAt: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("The vault is joined and unlocked.", systemImage: "checkmark.circle")
        .font(.headline).foregroundStyle(Palette.success)
      Text("Its accounts are downloading. The previous vault was kept at:").font(.callout)
      Text((keptAt as NSString).abbreviatingWithTildeInPath)
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Text("To switch back, load that file from Settings ▸ Vault.")
        .font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
  }

  // MARK: - Actions

  private func submit() {
    guard let endpoint, let vaultID else { return }
    working = true
    error = nil
    let bytes = Data(password.utf8)
    Task {
      switch mode {
      case .firstRun:
        error = await model.joinVault(endpoint: endpoint, vaultID: vaultID, password: bytes)
        if error == nil {
          password = ""
          SyncEndpoint.lastUsed = endpoint
        }
      case .replacingVault:
        switch await model.joinVaultInPlace(
          endpoint: endpoint, vaultID: vaultID, password: bytes, .app(backup))
        {
        case .success(let path):
          password = ""
          SyncEndpoint.lastUsed = endpoint
          keptAt = path
        case .failure(let failure):
          error = failure
        }
      }
      working = false
    }
  }
}

#Preview {
  JoinVaultView(mode: .firstRun)
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
