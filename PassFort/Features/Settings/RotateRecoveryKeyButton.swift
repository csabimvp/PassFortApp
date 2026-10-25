import PassFortVault
import SwiftUI

/// "Rotate…" for the recovery key: asks first, because the current key stops working at once, then
/// shows the new key in a sheet on the window the button is in. A failure says so instead of doing
/// nothing.
struct RotateRecoveryKeyButton: View {
  @Environment(AppModel.self) private var model

  @State private var confirming = false
  @State private var working = false
  @State private var presented: PresentedKey?
  @State private var error: AppError?

  var body: some View {
    Button("Rotate…") { confirming = true }
      .disabled(model.state != .unlocked || working)
      .alert("Rotate the recovery key?", isPresented: $confirming) {
        Button("Cancel", role: .cancel) {}
        Button("Rotate Key") { Task { await rotate() } }
      } message: {
        Text(
          "The current recovery key stops working at once. The new one is shown once, here, so "
            + "have somewhere to write it down.")
      }
      .sheet(item: $presented) { presented in
        RecoveryKeyPanel(key: presented.key, replacesPrevious: true) { self.presented = nil }
          .padding(24)
          .frame(width: 420)
          .interactiveDismissDisabled()
      }
      .alert(
        "Couldn't rotate the recovery key",
        isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
      ) {
        Button("OK") { error = nil }
      } message: {
        Text(error?.message ?? "")
      }
      // A key must not stay on screen once the vault locks.
      .onChange(of: model.state) { if model.state != .unlocked { presented = nil } }
  }

  private func rotate() async {
    working = true
    defer { working = false }
    switch await model.rotateRecoveryKey() {
    case .success(let key): presented = PresentedKey(key: key)
    case .failure(let failure): error = failure
    }
  }

  /// A key as a sheet item; a fresh id each time, so rotating twice shows the sheet twice.
  private struct PresentedKey: Identifiable {
    let id = UUID()
    let key: RecoveryKey
  }
}
