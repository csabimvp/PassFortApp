import PassFortVault
import SwiftUI

/// A problem that paused sync (`m5-sync.md` A.11): what happened, and the one sensible thing to
/// do about it. Never "continue anyway" -- a pinning failure or a forged record is exactly what
/// the checks are for. Closing the sheet leaves sync paused until Sync Now.
struct SyncProblemSheet: View {
  @Environment(\.dismiss) private var dismiss
  let problem: SyncError
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: "exclamationmark.triangle")
        .font(.title3.bold())
        .foregroundStyle(Palette.danger)
      Text(problem.message)
        .fixedSize(horizontal: false, vertical: true)
      if let advice {
        Text(advice)
          .font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text("Everything on this Mac is unchanged, and keeps working while sync is paused.")
        .font(.caption).foregroundStyle(.secondary)

      HStack {
        if opensSettings {
          SettingsLink { Text("Open Sync Settings…") }
        }
        Spacer()
        Button("Later") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Try Again") {
          dismiss()
          retry()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 440)
  }

  private var title: String {
    switch problem {
    case .pinningFailed: "Sync stopped: the server isn't trusted"
    case .serverRollback: "Sync stopped: the server went back in time"
    case .tamperedRecord: "Sync stopped: an account failed its check"
    case .unauthorized, .forbidden: "Sync stopped: the server refused this vault"
    default: "Sync is paused"
    }
  }

  /// What to do beyond retrying, when there is something.
  private var advice: String? {
    switch problem {
    case .unauthorized:
      "If the vault was put on the server again from another device, turn sync off here and "
        + "join it again, or turn sync on to upload this Mac's copy."
    case .serverRollback:
      "If you restored the server on purpose, turn sync off here, then on again to upload this "
        + "Mac's vault. Other devices will then need to join it again."
    case .notFound:
      "The server copy may have been deleted from another device. Turn sync off here, or on "
        + "again to upload this Mac's vault."
    case .noPins, .insecureEndpoint:
      "Check the server address in Settings ▸ Sync."
    default:
      nil
    }
  }

  private var opensSettings: Bool {
    switch problem {
    case .unauthorized, .serverRollback, .notFound, .noPins, .insecureEndpoint, .forbidden:
      true
    default:
      false
    }
  }
}
