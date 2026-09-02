import Foundation
import SwiftUI

/// The `.needsVault` screen: pick a master password (twice) and, by default,
/// generate a recovery key. Calibration + creation run in `AppModel.createVault`.
struct CreateVaultView: View {
  @Environment(AppModel.self) private var model
  @State private var password = ""
  @State private var confirm = ""
  @State private var withRecovery = true
  @State private var working = false
  @State private var error: AppError?

  private var passwordsMatch: Bool { !password.isEmpty && password == confirm }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Create a vault").font(.title2).bold()

      SecureField("Master password", text: $password)
        .textFieldStyle(.roundedBorder)
      SecureField("Repeat password", text: $confirm)
        .textFieldStyle(.roundedBorder)
      if !confirm.isEmpty, password != confirm {
        Text("Passwords don't match.").font(.caption).foregroundStyle(.red)
      }

      Toggle("Also create a recovery key", isOn: $withRecovery)
      Text("A recovery key is another way in if you forget this password. You'll see it once.")
        .font(.caption).foregroundStyle(.secondary)

      if let error {
        Label(error.message, systemImage: "xmark.octagon")
          .font(.callout).foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("Create vault", action: create)
          .keyboardShortcut(.defaultAction)
          .disabled(working || !passwordsMatch)
      }

      if working { ProgressView("Calibrating & creating…") }
    }
    .padding(32)
    .frame(width: 400)
    .disabled(working)
  }

  private func create() {
    working = true
    error = nil
    let bytes = Data(password.utf8)
    Task {
      error = await model.createVault(password: bytes, recovery: withRecovery)
      working = false
      if error == nil {
        password = ""
        confirm = ""
      }
    }
  }
}

#Preview {
  CreateVaultView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
