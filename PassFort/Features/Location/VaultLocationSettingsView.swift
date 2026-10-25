import AppKit
import SwiftUI

/// Settings ▸ Vault: where the vault file lives, and moving it. Local folders only -- a network
/// drive or a synced folder can corrupt an open database -- so those are for backups.
struct VaultLocationSettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(VaultLocationModel.self) private var location
  @Environment(BackupModel.self) private var backup: BackupModel?
  @State private var pendingFolder: URL?
  @State private var confirmingDefault = false
  @State private var startingNewVault = false
  @State private var loadingVault = false
  @State private var joiningVault = false

  private var canChange: Bool {
    model.state.allowsFileMoves && !location.isBusy && !location.needsRelaunch
  }

  var body: some View {
    Form {
      Section("Location") {
        LabeledContent("Vault file") {
          Text(location.displayPath).textSelection(.enabled).multilineTextAlignment(.trailing)
        }
        LabeledContent(
          "Kept in", value: location.isCustom ? "A folder you chose" : "PassFort's own storage")

        HStack {
          Button("Move Vault…", action: chooseFolder)
          Button("Use Default Location") { confirmingDefault = true }
            .disabled(!location.isCustom)
          if location.isBusy { ProgressView().controlSize(.small) }
        }
        .disabled(!canChange)

        status
      }

      Section {
        Text(
          "The vault can live on this Mac or an attached drive. Network drives and folders synced by "
            + "iCloud, Dropbox or similar are refused, because they can corrupt a vault that is "
            + "open. Use the Backup tab for those. Moving takes effect after PassFort restarts.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Replace vault") {
        HStack {
          Button("Start a New Vault…") { startingNewVault = true }
          Button("Load Vault…") { loadingVault = true }
          Button("Join a Synced Vault…") { joiningVault = true }
            .disabled(!model.syncAvailable)
        }
        .disabled(model.state != .unlocked || location.isBusy || location.needsRelaunch)
        Text(
          "Start a New Vault puts an empty vault in this one's place; Load Vault puts one from a "
            + "file there; Join a Synced Vault downloads one another device syncs. Either way the "
            + "current vault is kept beside it, never deleted, with its own sync settings. Unlock "
            + "the vault first.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 440)
    .padding()
    .sheet(isPresented: $startingNewVault) {
      NewVaultView().environment(model).environment(backup)
    }
    .sheet(isPresented: $loadingVault) {
      LoadVaultView().environment(model).environment(backup).environment(location)
    }
    .sheet(isPresented: $joiningVault) {
      JoinVaultView(mode: .replacingVault).environment(model).environment(backup)
    }
    .alert(
      "Move the vault?", isPresented: Binding(get: { pendingFolder != nil }, set: { if !$0 { pendingFolder = nil } }),
      presenting: pendingFolder
    ) { folder in
      Button("Move Vault") {
        pendingFolder = nil
        Task { await location.move(to: folder, .app(model, backup)) }
      }
      Button("Cancel", role: .cancel) { pendingFolder = nil }
    } message: { folder in
      Text(
        "PassFort will lock, copy the vault into “\(folder.lastPathComponent)”, check the copy, and "
          + "ask you to restart. The current vault is kept next to the old location as a safety copy.")
    }
    .alert("Move the vault back?", isPresented: $confirmingDefault) {
      Button("Move Vault") { Task { await location.useDefaultLocation(.app(model, backup)) } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "PassFort will lock, copy the vault back into its own storage, check the copy, and ask you "
          + "to restart. The vault in the chosen folder is kept there as a safety copy.")
    }
  }

  // MARK: - Status

  @ViewBuilder
  private var status: some View {
    switch location.step {
    case .idle, .working:
      EmptyView()
    case .failed(let message):
      VStack(alignment: .leading, spacing: 6) {
        Label(message, systemImage: "xmark.octagon").foregroundStyle(Palette.danger)
        Button("OK") { location.dismiss() }.controlSize(.small)
      }
    case .movedNeedsRelaunch(let moved):
      VStack(alignment: .leading, spacing: 6) {
        Label("The vault was moved to \(moved.destination).", systemImage: "checkmark.circle")
          .foregroundStyle(Palette.success)
        Text("Restart PassFort to start using it. Until then, leave the vault locked.")
          .font(.caption)
        Button("Restart PassFort") { AppRelauncher.relaunch() }
      }
    }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose Folder"
    panel.message = "Choose a folder on this Mac or an attached drive for the vault."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    pendingFolder = url
  }
}
