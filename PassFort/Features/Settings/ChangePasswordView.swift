import Foundation
import PassFortVault
import SwiftUI

/// Settings ▸ Security ▸ Change master password. Current password, the new one twice, and whether
/// to issue a fresh recovery key — the existing one stops working regardless (the re-wrap changes
/// the header salt its tag covers). With a new key, this sheet shows it once in place of the form.
struct ChangePasswordView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  @State private var current = ""
  @State private var new = ""
  @State private var confirm = ""
  @State private var issueRecoveryKey = true
  @State private var working = false
  @State private var error: AppError?
  /// The key the change issued, shown once; dropped with the sheet.
  @State private var newKey: RecoveryKey?

  private var canSubmit: Bool { !current.isEmpty && !new.isEmpty && new == confirm }

  var body: some View {
    Group {
      if let newKey {
        RecoveryKeyPanel(key: newKey, replacesPrevious: true) { dismiss() }
      } else {
        form
      }
    }
    .padding(24)
    .frame(width: 420)
    // A key must not stay on screen once the vault locks; neither should a half-filled form.
    .onChange(of: model.state) { if model.state != .unlocked { dismiss() } }
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Change master password").font(.title3).bold()

      SecureField("Current password", text: $current)
      SecureField("New password", text: $new)
      SecureField("Repeat new password", text: $confirm)
      if !confirm.isEmpty, new != confirm {
        Text("Passwords don't match.").font(.caption).foregroundStyle(Palette.danger)
      }

      Toggle("Issue a new recovery key", isOn: $issueRecoveryKey)
      Text(
        "Your current recovery key stops working either way. Backups made before now still "
          + "open with the old password."
      )
      .font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if let error {
        Label(error.message, systemImage: "xmark.octagon")
          .font(.callout).foregroundStyle(Palette.danger)
      }

      HStack {
        if working { ProgressView().controlSize(.small) }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Change Password", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(working || !canSubmit)
      }
    }
    .textFieldStyle(.roundedBorder)
    .disabled(working)
  }

  private func submit() {
    working = true
    error = nil
    let currentBytes = Data(current.utf8)
    let newBytes = Data(new.utf8)
    Task {
      let result = await model.changePassword(
        current: currentBytes, new: newBytes, issueRecoveryKey: issueRecoveryKey)
      working = false
      switch result {
      case .success(let key):
        current = ""
        new = ""
        confirm = ""
        if let key { newKey = key } else { dismiss() }
      case .failure(let failure):
        error = failure
      }
    }
  }
}

#Preview {
  ChangePasswordView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
