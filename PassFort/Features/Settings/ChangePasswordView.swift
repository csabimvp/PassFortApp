import Foundation
import SwiftUI

/// Settings ▸ General ▸ Change master password. Current password, the new one twice, and whether
/// to issue a fresh recovery key — the existing one stops working regardless (the re-wrap changes
/// the header salt its tag covers). On success with a new key, the main window shows it once.
struct ChangePasswordView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  @State private var current = ""
  @State private var new = ""
  @State private var confirm = ""
  @State private var issueRecoveryKey = true
  @State private var working = false
  @State private var error: AppError?

  private var canSubmit: Bool { !current.isEmpty && !new.isEmpty && new == confirm }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Change master password").font(.title3).bold()

      SecureField("Current password", text: $current)
      SecureField("New password", text: $new)
      SecureField("Repeat new password", text: $confirm)
      if !confirm.isEmpty, new != confirm {
        Text("Passwords don't match.").font(.caption).foregroundStyle(.red)
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
          .font(.callout).foregroundStyle(.red)
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
    .padding(24)
    .frame(width: 380)
    .disabled(working)
  }

  private func submit() {
    working = true
    error = nil
    let currentBytes = Data(current.utf8)
    let newBytes = Data(new.utf8)
    Task {
      error = await model.changePassword(
        current: currentBytes, new: newBytes, issueRecoveryKey: issueRecoveryKey)
      working = false
      if error == nil {
        current = ""
        new = ""
        confirm = ""
        dismiss()
      }
    }
  }
}

#Preview {
  ChangePasswordView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
