import Foundation
import SwiftUI

/// Settings ▸ Vault ▸ Start a New Vault. The current password, the new one twice, and the recovery
/// key choice. On success the main window shows the new vault (or its recovery key, once) and this
/// sheet says where the old vault was kept.
struct NewVaultView: View {
  @Environment(AppModel.self) private var model
  @Environment(BackupModel.self) private var backup: BackupModel?
  @Environment(\.dismiss) private var dismiss

  @State private var current = ""
  @State private var new = ""
  @State private var confirm = ""
  @State private var withRecovery = true
  @State private var working = false
  @State private var error: AppError?
  /// Where the old vault was kept, once the new one exists.
  @State private var keptAt: String?

  private var canSubmit: Bool { !current.isEmpty && !new.isEmpty && new == confirm }

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
    .frame(width: 400)
  }

  // MARK: - Form

  private var form: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Start a new vault").font(.title3).bold()

      Text(
        "PassFort replaces this vault with an empty one. The current vault is set aside next to it "
          + "and kept, never deleted, so you can import accounts from it later."
      )
      .font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      SecureField("Current password", text: $current)
      SecureField("New vault's password", text: $new)
      SecureField("Repeat new password", text: $confirm)
      if !confirm.isEmpty, new != confirm {
        Text("Passwords don't match.").font(.caption).foregroundStyle(Palette.danger)
      }

      Toggle("Also create a recovery key", isOn: $withRecovery)

      if let error {
        Label(error.message, systemImage: "xmark.octagon")
          .font(.callout).foregroundStyle(Palette.danger)
      }

      HStack {
        if working { ProgressView().controlSize(.small) }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Start New Vault", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(working || !canSubmit)
      }
    }
    .disabled(working)
  }

  private func done(_ keptAt: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("A new, empty vault is ready.", systemImage: "checkmark.circle")
        .font(.headline).foregroundStyle(Palette.success)
      Text("The previous vault was kept at:").font(.callout)
      Text((keptAt as NSString).abbreviatingWithTildeInPath)
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Text(
        "To bring accounts over, choose that file in Tools ▸ Import from Another Vault… and unlock "
          + "it with its old password. Its backups stay in the backup folder; they aren't pruned."
      )
      .font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
  }

  private func submit() {
    working = true
    error = nil
    let currentBytes = Data(current.utf8)
    let newBytes = Data(new.utf8)
    Task {
      let result = await model.startNewVault(
        current: currentBytes, password: newBytes, recovery: withRecovery, .app(backup))
      working = false
      switch result {
      case .success(let path):
        current = ""
        new = ""
        confirm = ""
        keptAt = path
      case .failure(let failure):
        error = failure
      }
    }
  }
}

extension AppModel.NewVaultHooks {
  /// The app's side: a mid-run backup refuses it, and backups pause while the files are swapped.
  /// They resume afterwards, now backing up the new vault.
  static func app(_ backup: BackupModel?) -> Self {
    Self(
      begin: {
        if backup?.isRunning == true { return "A backup is running. Try again in a moment." }
        backup?.setPaused(true)
        return nil
      },
      end: { backup?.setPaused(false) })
  }
}

#Preview {
  NewVaultView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
