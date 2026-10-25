import AppKit
import Foundation
import PassFortVault
import SwiftUI

/// The `.locked` / `.unlocking` screen: a `SecureField` (with a Caps Lock warning), an Unlock
/// button, and a banner for the last failure. The rollback banner carries the one action the
/// user can take themselves — the GUI's `verify --accept-restore`.
struct UnlockView: View {
  @Environment(AppModel.self) private var model
  /// Optional so previews that only inject `AppModel` keep working.
  @Environment(BackupModel.self) private var backup: BackupModel?
  @State private var password = ""
  @FocusState private var passwordFocused: Bool
  @State private var capsLockOn = false

  var body: some View {
    VStack(spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 80, height: 80)
        .accessibilityHidden(true)
      Text("PassFort")
        .font(.title2.weight(.semibold))

      VStack(alignment: .leading, spacing: 6) {
        SecureField("Master password", text: $password)
          .textFieldStyle(.roundedBorder)
          .focused($passwordFocused)
        if capsLockOn {
          Label("Caps Lock is on", systemImage: "capslock.fill")
            .font(.caption)
            .foregroundStyle(Palette.warning)
        }
      }
      .frame(maxWidth: 280)

      // A.8: another device changed the password; this Mac adopts it at an unlock that uses it.
      if model.headerChangedElsewhere {
        Label(SyncError.headerChangedElsewhere.message, systemImage: "info.circle")
          .font(.callout)
          .foregroundStyle(Palette.warning)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 320)
      }

      if case .locked(let error?) = model.state {
        errorBanner(error)
          .frame(maxWidth: 320)
          .transition(.opacity)
      }

      Button(action: unlock) {
        Text("Unlock").frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .frame(maxWidth: 280)
      .keyboardShortcut(.defaultAction)
      .disabled(password.isEmpty || model.state.isUnlocking)

      if model.state.isUnlocking {
        ProgressView("Deriving key…")
      }

      if !model.state.isUnlocking {
        RestoreBackupButton()
          .buttonStyle(.link)
          .foregroundStyle(Palette.primary)
          .font(.caption)
      }

      // A failed automatic backup happens while locked, with nobody watching -- say so here.
      if let failure = backup?.failureMessage {
        Label("Last backup failed. \(failure)", systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(Palette.warning)
          .frame(maxWidth: 320)
      }
    }
    .padding(40)
    .onModifierKeysChanged { _, keys in capsLockOn = keys.contains(.capsLock) }
    .animation(.default, value: model.state)
    .onAppear { passwordFocused = true }
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
        .foregroundStyle(Palette.danger)
    }
  }
}

#Preview {
  UnlockView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
