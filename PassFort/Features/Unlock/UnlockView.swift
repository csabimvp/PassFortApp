import Foundation
import SwiftUI

/// The `.locked` / `.unlocking` screen: a `SecureField`, an Unlock button, and a
/// banner for the last failure. The rollback banner carries the one action the
/// user can take themselves — the GUI's `verify --accept-restore`.
struct UnlockView: View {
  @Environment(AppModel.self) private var model
  @State private var password = ""

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "lock.fill")
        .font(.largeTitle)
        .foregroundStyle(.secondary)

      SecureField("Master password", text: $password)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 280)

      if case .locked(let error?) = model.state {
        errorBanner(error)
          .frame(maxWidth: 320)
          .transition(.opacity)
      }

      Button("Unlock", action: unlock)
        .keyboardShortcut(.defaultAction)
        .disabled(password.isEmpty || model.state.isUnlocking)

      if model.state.isUnlocking {
        ProgressView("Deriving key…")
      }
    }
    .padding(40)
    .animation(.default, value: model.state)
    .onChange(of: model.state) { _, state in
      if state == .unlocked { password = "" }  // keep it on failure so a retry works
    }
  }

  private func unlock() {
    Task { await model.unlock(password: Data(password.utf8)) }
  }

  @ViewBuilder
  private func errorBanner(_ error: AppError) -> some View {
    switch error {
    case .rolledBack:
      VStack(spacing: 8) {
        Label(error.message, systemImage: "clock.arrow.circlepath")
        Text(
          "A restored backup and a rolled-back file look the same. "
            + "If you restored a backup on purpose, accept it:"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        Button("This was a backup I restored") {
          Task { await model.acceptRestoreAndRetry(password: Data(password.utf8)) }
        }
        .disabled(password.isEmpty || model.state.isUnlocking)
      }

    default:
      Label(error.message, systemImage: "xmark.octagon")
        .foregroundStyle(.red)
    }
  }
}

#Preview {
  UnlockView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
