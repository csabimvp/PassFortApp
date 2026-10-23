import AppKit
import SwiftUI

/// Settings ▸ Backup. Works while the vault is locked: a backup copies the sealed file and needs
/// no key. Choosing the folder is the only thing here that touches AppKit (`NSOpenPanel`).
struct BackupSettingsView: View {
  @Environment(BackupModel.self) private var backup
  @AppStorage(BackupModel.Keys.onLock) private var backsUpOnLock = true
  @AppStorage(BackupModel.Keys.keep) private var keep = BackupModel.defaultKeep
  @State private var pickerError: String?

  var body: some View {
    Form {
      Section("Destination") {
        LabeledContent("Folder", value: backup.folderName ?? "None chosen")
        HStack {
          Button("Choose Folder…", action: chooseFolder)
          Button("Remove") { backup.removeFolder() }
            .disabled(!backup.hasFolder)
        }
        if let pickerError {
          Label(pickerError, systemImage: "xmark.octagon").foregroundStyle(Palette.danger)
        }
      }

      Section("Backups") {
        HStack {
          Button("Back Up Now") { Task { await backup.backUpNow() } }
            .disabled(!backup.hasFolder || backup.isRunning)
          if backup.isRunning { ProgressView().controlSize(.small) }
        }
        statusLine

        Toggle("Back up automatically when locking", isOn: $backsUpOnLock)
          .disabled(!backup.hasFolder)
        Picker("Keep", selection: $keep) {
          Text("Latest only").tag(1)
          Text("Newest 5").tag(5)
          Text("Newest 10").tag(10)
          Text("Newest 30").tag(30)
        }
        .disabled(!backup.hasFolder)
        if keep == 1 {
          Text("Each backup replaces the previous one, so there is no history to go back to.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }

      Section("Restore") {
        RestoreBackupButton()
        Text("Replaces the vault on this Mac with a backup. The current vault is kept as a safety copy.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        Text(
          "A backup is a copy of your encrypted vault. It is as safe as the vault itself, "
            + "and it needs no password to make. Restoring one brings back an older vault.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 440)
    .padding()
  }

  // MARK: - Status

  @ViewBuilder
  private var statusLine: some View {
    switch backup.status {
    case .idle, .running:
      if !backup.hasFolder {
        Text("Choose a folder, such as a share on your NAS, to start.")
          .font(.caption).foregroundStyle(.secondary)
      } else if backup.status == .idle {
        Text("No backup yet.").font(.caption).foregroundStyle(.secondary)
      }
    case .succeeded(let date, let version):
      Text(
        "Last backup \(date.formatted(date: .abbreviated, time: .shortened)) · version \(version)"
      )
      .font(.caption).foregroundStyle(.secondary)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.caption).foregroundStyle(Palette.warning)
    }
  }

  // MARK: - Folder picker

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Use Folder"
    panel.message = "Choose where PassFort should keep its backups."
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      try backup.setFolder(url)
      pickerError = nil
    } catch {
      pickerError = "Couldn't remember that folder: \(error.localizedDescription)"
    }
  }
}

#Preview {
  BackupSettingsView().environment(BackupModel())
}
