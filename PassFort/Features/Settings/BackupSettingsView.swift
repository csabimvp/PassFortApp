import AppKit
import SwiftUI

/// Settings ▸ Backup. Works while the vault is locked: a backup copies the sealed file and needs
/// no key. With no folder yet it is one empty state and one button. Choosing the folder is the only
/// thing here that touches AppKit (`NSOpenPanel`). Restoring is File ▸ Restore from Backup….
struct BackupSettingsView: View {
  @Environment(BackupModel.self) private var backup
  @AppStorage(BackupModel.Keys.onLock) private var backsUpOnLock = true
  @AppStorage(BackupModel.Keys.keep) private var keep = BackupModel.defaultKeep
  @State private var pickerError: String?

  var body: some View {
    Form {
      if backup.hasFolder {
        destination
        backups
      } else {
        emptyState
      }
    }
    .settingsTab()
    .task { await backup.refreshCount() }
  }

  // MARK: - No folder

  private var emptyState: some View {
    Section {
      VStack(spacing: 10) {
        Image(systemName: "externaldrive")
          .font(.title2)
          .foregroundStyle(Palette.primary)
          .frame(width: 44, height: 44)
          .background(Palette.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
        Text("Back up to a folder you choose").font(.title3.weight(.semibold))
        Text(
          "A share on your NAS or an external drive works well. PassFort copies the encrypted "
            + "vault there each time it locks."
        )
        .font(.callout).foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        Button("Choose Folder…", action: chooseFolder)
          .buttonStyle(.borderedProminent)
          .padding(.top, 4)
        pickerFailure
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
    } footer: {
      SettingsFooter("Backups need no password and run while the vault is locked.")
    }
  }

  // MARK: - Folder chosen

  private var destination: some View {
    Section("Destination") {
      LabeledContent {
        HStack {
          Button("Show in Finder", action: showFolder)
            .disabled(backup.folderURL == nil)
          Button("Change…", action: chooseFolder)
        }
      } label: {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(backup.folderName ?? "")
            if let url = backup.folderURL {
              Text((url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            }
          }
        } icon: {
          Image(systemName: "folder.fill").symbolRenderingMode(.multicolor)
        }
      }
      LabeledContent {
        Button("Stop Using Folder") { backup.removeFolder() }
      } label: {
        Text("Backups already made stay in the folder.").foregroundStyle(.secondary)
      }
      pickerFailure
    }
  }

  private var backups: some View {
    Section {
      LabeledContent {
        HStack {
          if backup.isRunning { ProgressView().controlSize(.small) }
          Button("Back Up Now") { Task { await backup.backUpNow() } }
            .disabled(backup.isRunning)
        }
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text("Last backup")
          lastBackup
        }
      }

      Toggle("Back up when the vault locks", isOn: $backsUpOnLock)
      Picker("Keep", selection: $keep) {
        Text("Latest only").tag(1)
        Text("Newest 5").tag(5)
        Text("Newest 10").tag(10)
        Text("Newest 30").tag(30)
      }
      if keep == 1 {
        Text("Each backup replaces the previous one, so there is no history to go back to.")
          .font(.caption).foregroundStyle(.secondary)
      }
    } header: {
      Text("Backups")
    } footer: {
      SettingsFooter(
        "A backup is the encrypted vault file: as safe as the vault, made without the password, "
          + "even while locked. To bring one back, use File ▸ Restore from Backup….")
    }
  }

  // MARK: - Status

  /// When the last backup ran, in relative time, and how many the folder holds -- not the vault
  /// version, which means nothing here.
  @ViewBuilder
  private var lastBackup: some View {
    switch backup.status {
    case .idle:
      Text("No backup yet").font(.caption).foregroundStyle(.secondary)
    case .running:
      Text("Backing up…").font(.caption).foregroundStyle(.secondary)
    case .succeeded(let date, _):
      TimelineView(.periodic(from: .now, by: 60)) { context in
        HStack(spacing: 4) {
          Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Palette.success)
          Text(Self.summary(of: date, count: backup.backupCount, now: context.date))
        }
        .font(.caption).foregroundStyle(.secondary)
      }
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.caption).foregroundStyle(Palette.warning)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// "2 hours ago · 8 in the folder".
  static func summary(of date: Date, count: Int?, now: Date) -> String {
    let when =
      now.timeIntervalSince(date) < 60
      ? "Just now" : date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    guard let count else { return when }
    return "\(when) · \(count) in the folder"
  }

  @ViewBuilder
  private var pickerFailure: some View {
    if let pickerError {
      Label(pickerError, systemImage: "xmark.octagon").foregroundStyle(Palette.danger)
    }
  }

  // MARK: - Folder

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
      Task { await backup.refreshCount() }
    } catch {
      pickerError = "Couldn't remember that folder: \(error.localizedDescription)"
    }
  }

  /// The folder is a security-scoped bookmark; Finder is handed it while access is held.
  private func showFolder() {
    guard let url = backup.folderURL else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    NSWorkspace.shared.open(url)
  }
}

#Preview {
  BackupSettingsView().environment(BackupModel())
}
