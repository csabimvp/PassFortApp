import AppKit
import PassFortVault
import SwiftUI

/// "Restore from Backup…" as a link -- on the Unlock screen and the Create screen (a new Mac with
/// no vault yet). It only asks: the picker and the alerts are `RestoreBackupFlow`, on the vault
/// window's root, which File ▸ Restore from Backup… opens too. Callers style it
/// (`.buttonStyle(.link)` etc.).
struct RestoreBackupButton: View {
  @Environment(AppModel.self) private var model
  /// Optional so previews that only inject `AppModel` keep working.
  @Environment(VaultLocationModel.self) private var location: VaultLocationModel?

  var body: some View {
    Button("Restore from Backup…") { model.showingRestore = true }
      .disabled(!RestoreBackupFlow.isAllowed(model, location))
  }
}

/// The restore itself: the backup picker, the confirmation and the result, opened by
/// `AppModel.showingRestore`. It owns its `RestoreModel`; the file work and the ordering rules live
/// there. Attached once, to the vault window's root.
struct RestoreBackupFlow: ViewModifier {
  @Environment(AppModel.self) private var model
  /// Optional so previews that only inject `AppModel` keep working.
  @Environment(BackupModel.self) private var backup: BackupModel?
  @Environment(VaultLocationModel.self) private var location: VaultLocationModel?
  @State private var restore = RestoreModel()

  /// Not while a vault is being created or unlocked (the files are in use), nor while the vault's
  /// location is unusable or waiting for a relaunch.
  static func isAllowed(_ model: AppModel, _ location: VaultLocationModel?) -> Bool {
    model.state.allowsFileMoves && location?.isUsable != false && location?.needsRelaunch != true
  }

  func body(content: Content) -> some View {
    content
      .onAppear { if let location { restore.databasePath = location.databasePath } }
      .onChange(of: model.showingRestore) {
        guard model.showingRestore else { return }
        model.showingRestore = false
        if !restore.isBusy, Self.isAllowed(model, location) { pick() }
      }
      .alert(
        "Restore this backup?", isPresented: confirmingBinding, presenting: candidate
      ) { candidate in
        Button(
          candidate.isDifferentVault ? "Replace With a Different Vault" : "Restore",
          role: .destructive
        ) {
          Task { await restore.confirm(hooks) }
        }
        Button("Cancel", role: .cancel) { restore.cancel() }
      } message: { candidate in
        Text(confirmationText(for: candidate))
      }
      .alert(resultTitle, isPresented: resultBinding) {
        Button("OK") { restore.dismiss() }
      } message: {
        Text(resultText)
      }
  }

  // MARK: - Picking

  private func pick() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = backup?.folderURL
    panel.prompt = "Choose Backup"
    panel.message = "Choose a PassFort backup to restore."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task { await restore.choose(url) }
  }

  // MARK: - Hooks into the rest of the app

  private var hooks: RestoreModel.Hooks {
    RestoreModel.Hooks(
      begin: {
        if backup?.isRunning == true { return "A backup is running. Try again in a moment." }
        backup?.setPaused(true)  // no lock-time backup may read the files mid-swap
        return nil
      },
      releaseVault: { if model.state != .needsVault { await model.lockAndRelease() } },
      reload: { model.reloadAfterRestore() },
      end: { backup?.setPaused(false) })
  }

  // MARK: - Alerts

  private var candidate: RestoreModel.Candidate? {
    if case .confirming(let candidate) = restore.step { return candidate }
    return nil
  }

  /// Dismissal is explicit (the Cancel button): a binding setter that cancelled would also fire
  /// when "Restore" is pressed and throw away the staged file before `confirm` runs.
  private var confirmingBinding: Binding<Bool> {
    Binding(get: { candidate != nil }, set: { _ in })
  }

  private var resultBinding: Binding<Bool> {
    Binding(
      get: {
        switch restore.step {
        case .restored, .failed: return true
        default: return false
        }
      },
      set: { shown in if !shown { restore.dismiss() } })
  }

  private var resultTitle: String {
    if case .restored = restore.step { return "Backup restored" }
    return "Couldn't restore"
  }

  private var resultText: String {
    switch restore.step {
    case .restored(let previous):
      var text = "Unlock it with the master password it had when the backup was made."
      if let previous {
        text += " Your previous vault was kept next to it as “\(previous)”."
      }
      return text
    case .failed(let message):
      return message
    default:
      return ""
    }
  }

  private func confirmationText(for candidate: RestoreModel.Candidate) -> String {
    var lines: [String] = []
    let made = candidate.madeAt.map { $0.formatted(date: .abbreviated, time: .shortened) }
    lines.append("Backup from \(made ?? candidate.fileName), version \(candidate.backup.vaultVersion).")

    if let current = candidate.current {
      lines.append("The vault on this Mac is version \(current.vaultVersion).")
      if candidate.isDifferentVault {
        lines.append("This backup is from a DIFFERENT vault than the one on this Mac.")
      } else if candidate.isOlderThanCurrent {
        lines.append("Anything you added or changed since this backup will be missing.")
      }
      lines.append(
        "Your current vault is kept as a safety copy. The restored vault opens with the master "
          + "password it had when the backup was made.")
    } else {
      lines.append("There is no vault on this Mac yet. It opens with the master password it had when the backup was made.")
    }
    return lines.joined(separator: "\n\n")
  }
}

#Preview {
  RestoreBackupButton().environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
