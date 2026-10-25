import AppKit
import PassFortVault
import SwiftUI

/// Settings ▸ Sync ▸ Add a Device (`m5-sync.md` A.11): what another device needs to join this
/// vault -- the server and the vault id, as text and as a QR code of the `SyncInvite` link. It
/// holds no secret: the joining device still needs the master password.
struct AddDeviceSheet: View {
  @Environment(\.dismiss) private var dismiss
  let invite: SyncInvite

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Add a device").font(.title3).bold()
      Text(
        "On the other Mac, choose Join a Synced Vault (on its first screen, or File ▸ Join "
          + "Synced Vault…) and paste the invite link, or type the server and vault ID. It will ask "
          + "for this vault's master password; nothing here is secret without it.")
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(alignment: .top, spacing: 18) {
        if let image = QRCodeImage.make(invite.url.absoluteString) {
          Image(decorative: image, scale: 2)
            .interpolation(.none)
            .resizable()
            .frame(width: 168, height: 168)
            .padding(8)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("QR code of the invite link")
        }
        VStack(alignment: .leading, spacing: 10) {
          field("Invite link", invite.url.absoluteString)
          field("Server", invite.endpoint.absoluteString)
          field("Vault ID", invite.vaultID.uuidString.lowercased())
        }
      }

      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 560)
    .copyToast(bottomInset: 60)  // above the Done row
  }

  private func field(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(value)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        CopyButton(label: label, value: value, kind: .plain)
      }
    }
  }
}
