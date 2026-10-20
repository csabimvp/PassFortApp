import AppKit
import SwiftUI

/// Shown instead of the whole app when a chosen vault folder can't be reached at launch (an
/// unplugged drive, a deleted folder). It must never fall through to "Create a vault": that would
/// quietly start a second, empty vault in the default location.
struct VaultLocationUnavailableView: View {
  @Environment(AppModel.self) private var model
  @Environment(VaultLocationModel.self) private var location
  @Environment(BackupModel.self) private var backup: BackupModel?
  @State private var pendingFolder: URL?
  @State private var confirmingDefault = false

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "externaldrive.badge.exclamationmark")
        .font(.largeTitle).foregroundStyle(.secondary)
      Text("Your vault isn't available").font(.title2).bold()
      Text(location.unavailableReason ?? "PassFort can't reach the folder your vault is in.")
        .multilineTextAlignment(.center)
      Text(location.displayPath)
        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        .textSelection(.enabled)

      Button("Restart and Try Again") { AppRelauncher.relaunch() }
        .keyboardShortcut(.defaultAction)

      Divider().frame(maxWidth: 320)
      Text("Moved the vault, or done with that drive?").font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Choose Another Folder…", action: chooseFolder)
        Button("Use Default Location") { confirmingDefault = true }
      }
      .disabled(location.isBusy)

      switch location.step {
      case .failed(let message):
        Label(message, systemImage: "xmark.octagon").font(.callout).foregroundStyle(.red)
      case .movedNeedsRelaunch:
        VStack(spacing: 6) {
          Label("Saved. Restart PassFort to use the new location.", systemImage: "checkmark.circle")
            .foregroundStyle(.green)
          Button("Restart PassFort") { AppRelauncher.relaunch() }
        }
      case .idle, .working:
        EmptyView()
      }
    }
    .padding(40)
    .frame(maxWidth: 460)
    .pfBackground()
    .alert(
      "Look for the vault there?",
      isPresented: Binding(get: { pendingFolder != nil }, set: { if !$0 { pendingFolder = nil } }),
      presenting: pendingFolder
    ) { folder in
      Button("Use This Folder") {
        pendingFolder = nil
        Task { await location.move(to: folder, .app(model, backup)) }
      }
      Button("Cancel", role: .cancel) { pendingFolder = nil }
    } message: { folder in
      Text(
        "PassFort will look for its vault in “\(folder.lastPathComponent)” (in a PassFort folder "
          + "there) after a restart. If there isn't one, you'll be asked to create a new vault "
          + "there. Nothing is deleted.")
    }
    .alert("Use the default location?", isPresented: $confirmingDefault) {
      Button("Use Default") { Task { await location.useDefaultLocation(.app(model, backup)) } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "After a restart PassFort will use its own storage. Your vault stays on the missing "
          + "drive, untouched. If there is no vault in the default location you'll be asked to "
          + "create a new one, or you can restore a backup.")
    }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose Folder"
    panel.message = "Choose the folder that contains (or should contain) the PassFort folder."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    pendingFolder = url
  }
}
