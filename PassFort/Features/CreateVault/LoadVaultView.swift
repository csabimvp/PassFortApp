import AppKit
import Foundation
import SwiftUI

/// File ▸ Open Vault (the code's name for it is "load": `AppModel.loadVault`, the `pre-load`
/// label). Choose a vault file and type its password; on success the main window shows that vault,
/// unlocked, and this sheet says where the previous vault was kept.
struct LoadVaultView: View {
  @Environment(AppModel.self) private var model
  @Environment(BackupModel.self) private var backup: BackupModel?
  @Environment(VaultLocationModel.self) private var location: VaultLocationModel?
  @Environment(\.dismiss) private var dismiss

  @State private var file: URL?
  @State private var password = ""
  @State private var working = false
  @State private var error: AppError?
  /// Where the previous vault was kept, once the chosen one is live.
  @State private var keptAt: String?

  private var canSubmit: Bool { file != nil && !password.isEmpty }

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
      Text("Open a vault").font(.title3).bold()

      Text(
        "PassFort replaces this vault with the one you choose: from another Mac, the command line, "
          + "or one set aside by New Vault. The current vault is set aside next to it and "
          + "kept, never deleted. The file you choose is copied, not moved."
      )
      .font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack {
        Text(file?.lastPathComponent ?? "No vault chosen")
          .foregroundStyle(file == nil ? .secondary : .primary)
          .lineLimit(1).truncationMode(.middle)
        Spacer()
        Button("Choose…", action: choose)
      }

      SecureField("That vault's password", text: $password)

      if let error {
        Label(error.message, systemImage: "xmark.octagon")
          .font(.callout).foregroundStyle(Palette.danger)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        if working { ProgressView().controlSize(.small) }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Open Vault", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(working || !canSubmit)
      }
    }
    .disabled(working)
  }

  private func done(_ keptAt: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("The vault is open and unlocked.", systemImage: "checkmark.circle")
        .font(.headline).foregroundStyle(Palette.success)
      Text("The previous vault was kept at:").font(.callout)
      Text((keptAt as NSString).abbreviatingWithTildeInPath)
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Text("To switch back, open that file the same way.")
        .font(.caption).foregroundStyle(.secondary)

      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
  }

  // MARK: - Actions

  /// Opens in the live vault's folder, where the files set aside by an earlier swap are.
  private func choose() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if let location {
      panel.directoryURL = URL(fileURLWithPath: location.databasePath).deletingLastPathComponent()
    }
    panel.prompt = "Choose Vault"
    panel.message = "Choose the PassFort vault to open."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    file = url
    error = nil
  }

  private func submit() {
    guard let file else { return }
    working = true
    error = nil
    let bytes = Data(password.utf8)
    Task {
      let result = await model.loadVault(from: file, password: bytes, .app(backup))
      working = false
      switch result {
      case .success(let path):
        password = ""
        keptAt = path
      case .failure(let failure):
        error = failure
      }
    }
  }
}

#Preview {
  LoadVaultView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
