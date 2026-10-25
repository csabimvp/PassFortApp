import AppKit
import SwiftUI

/// Settings ▸ Vault: where the vault file lives, and moving it. Local folders only -- a network
/// drive or a synced folder can corrupt an open database -- so those are for backups. Putting
/// another vault in this one's place is in the File menu (`VaultFileCommands`).
struct VaultLocationSettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(VaultLocationModel.self) private var location
  @Environment(BackupModel.self) private var backup: BackupModel?
  @State private var pendingFolder: URL?
  @State private var confirmingDefault = false

  private var canChange: Bool {
    model.state.allowsFileMoves && !location.isBusy && !location.needsRelaunch
  }

  var body: some View {
    Form {
      Section {
        LabeledContent {
          Button("Show in Finder", action: showInFinder)
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text("Vault file")
            Text(location.displayPath)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1).truncationMode(.middle)
              .textSelection(.enabled)
              .help(location.displayPath)
          }
        }

        LabeledContent {
          HStack {
            if location.isBusy { ProgressView().controlSize(.small) }
            Button("Move Back to Default…") { confirmingDefault = true }
              .disabled(!location.isCustom)
            Button("Move…", action: chooseFolder)
          }
          .disabled(!canChange)
        } label: {
          Text(location.isCustom ? "A folder you chose" : "PassFort's own storage")
            .foregroundStyle(.secondary)
        }

        status
      } header: {
        Text("Location")
      } footer: {
        SettingsFooter(
          "This Mac or an attached drive. Network and cloud-synced folders are refused; use Backup "
            + "for those. A move takes effect after PassFort restarts.")
      }

      Section {
        Label("To start, open or join another vault, use the File menu.", systemImage: "info.circle")
          .foregroundStyle(.secondary)
      }
    }
    .settingsTab()
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

  private func showInFinder() {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: location.databasePath)])
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
