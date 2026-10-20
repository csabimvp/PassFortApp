import SwiftUI

/// Shown instead of the whole app after the vault location changed: this process still points at
/// the old place, so letting the user keep editing would write to a vault that is no longer the one.
struct RelaunchRequiredView: View {
  @Environment(VaultLocationModel.self) private var location

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "arrow.triangle.2.circlepath")
        .font(.largeTitle).foregroundStyle(.secondary)
      Text("Restart to finish").font(.title2).bold()
      if case .movedNeedsRelaunch(let moved) = location.step {
        Text("Your vault is now at \(moved.destination). PassFort needs to restart to open it from there.")
          .multilineTextAlignment(.center)
        if let old = moved.oldKeptAs {
          Text("The old copy was kept as “\(old)”.").font(.caption).foregroundStyle(.secondary)
        }
      }
      HStack {
        Button("Restart PassFort") { AppRelauncher.relaunch() }
          .keyboardShortcut(.defaultAction)
        Button("Quit") { AppRelauncher.quit() }
      }
    }
    .padding(40)
    .frame(maxWidth: 460)
    .pfBackground()
  }
}
