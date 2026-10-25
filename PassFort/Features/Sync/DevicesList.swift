import PassFortVault
import SwiftUI

/// Settings ▸ Sync ▸ Devices (`m5-sync.md` A.11): every device syncing this vault, as the server
/// lists them, newest first, with this Mac marked, and Add a Device… in the header. Removing one
/// stops it holding back the server's clean-up of deleted accounts.
struct DevicesList: View {
  let sync: SyncController
  /// Add a Device…: the caller shows the invite.
  let addDevice: () -> Void

  @State private var loading = false
  @State private var error: String?
  @State private var removing: DeviceInfoDTO?

  var body: some View {
    Section {
      ForEach(sync.devices, id: \.id) { device in
        row(device)
      }
      if sync.devices.isEmpty, !loading, error == nil {
        Text("No devices listed yet.").foregroundStyle(.secondary)
      }
      if let error {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.caption).foregroundStyle(Palette.warning)
          .fixedSize(horizontal: false, vertical: true)
      }
    } header: {
      HStack {
        Text("Devices")
        Spacer()
        if loading { ProgressView().controlSize(.small) }
        IconButton("Refresh devices", systemImage: "arrow.clockwise") {
          Task { await refresh() }
        }
        .disabled(loading)
        Button("Add a Device…", action: addDevice).controlSize(.small)
      }
    } footer: {
      SettingsFooter(
        "Removing a device stops it holding back the server's clean-up of deleted accounts.")
    }
    .task { await refresh() }
    .confirmationDialog(
      "Remove “\(removing?.name ?? "")”?",
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      titleVisibility: .visible, presenting: removing
    ) { device in
      Button("Remove Device", role: .destructive) { Task { await remove(device) } }
    } message: { _ in
      Text(
        "It keeps its own copy of the vault. If it syncs again, it downloads everything afresh "
          + "and uploads whatever the server lacks, so an account deleted meanwhile may come back.")
    }
  }

  private func row(_ device: DeviceInfoDTO) -> some View {
    let isThisMac = device.id == sync.device.id
    return LabeledContent {
      HStack(spacing: 8) {
        Text(device.lastSeenAt.formatted(.relative(presentation: .named)))
          .font(.caption).foregroundStyle(.secondary)
        if !isThisMac {
          IconButton("Remove \(device.name)", systemImage: "minus.circle") { removing = device }
        }
      }
    } label: {
      Label {
        HStack(spacing: 6) {
          Text(device.name)
          if isThisMac {
            Text("This Mac").font(.caption2.weight(.semibold))
              .padding(.horizontal, 6).padding(.vertical, 1)
              .background(.quaternary, in: Capsule())
          }
        }
      } icon: {
        Image(systemName: device.platform.symbol).foregroundStyle(.secondary)
      }
    }
  }

  private func refresh() async {
    loading = true
    defer { loading = false }
    do {
      try await sync.refreshDevices()
      error = nil
    } catch let failure as SyncError {
      error = "Couldn't list the devices. " + failure.message
    } catch {
      self.error = "Couldn't list the devices."
    }
  }

  private func remove(_ device: DeviceInfoDTO) async {
    do {
      try await sync.removeDevice(device.id)
      error = nil
    } catch let failure as SyncError {
      error = "Couldn't remove “\(device.name)”. " + failure.message
    } catch {
      self.error = "Couldn't remove “\(device.name)”."
    }
  }
}

extension DevicePlatform {
  var symbol: String {
    switch self {
    case .macos: "laptopcomputer"
    case .ios: "iphone"
    case .cli: "terminal"
    case .web: "globe"
    }
  }
}
