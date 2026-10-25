import AppKit
import PassFortVault
import SwiftUI

/// Settings ▸ Sync (`m5-sync.md` A.11): turn sync on for the open vault, or -- when it is on --
/// its status, the server, the vault id other devices join with, and turning it off. Sync
/// belongs to a vault, not to the Mac: each vault carries its own settings in its file.
struct SyncSettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var endpointText = SyncEndpoint.lastUsed?.absoluteString ?? ""
  @State private var enrollSecret = ""
  @State private var working = false
  @State private var error: String?
  @State private var confirmingOff = false
  @State private var invite: SyncInvite?

  var body: some View {
    Form {
      if model.state != .unlocked {
        LockedSettingsNotice(message: "Unlock it to see or change how this vault syncs.")
      } else if !model.syncAvailable {
        Section("Sync") {
          Text(
            "PassFort can't store this Mac's device identity in its own storage, so it can't "
              + "sync. Check that its Application Support folder is writable."
          )
          .foregroundStyle(Palette.warning)
        }
      } else if let sync = model.sync {
        if let state = sync.state {
          enabled(sync, state)
        } else {
          disabled(sync)
        }
      }
    }
    .settingsTab()
    .sheet(item: $invite) { invite in
      AddDeviceSheet(invite: invite)
    }
  }

  // MARK: - Off

  @ViewBuilder
  private func disabled(_ sync: SyncController) -> some View {
    Section("Sync") {
      TextField(
        "Server", text: $endpointText,
        prompt: Text("https://….azurestaticapps.net/api/v1"))
      SecureField("Enrollment secret", text: $enrollSecret)
      failure
      HStack {
        if working { ProgressView().controlSize(.small) }
        Spacer()
        Button("Turn On Sync") { Task { await enable(sync) } }
          .disabled(working || SyncEndpoint.parse(endpointText) == nil || enrollSecret.isEmpty)
      }
    }
    Section {
      Text(
        "The server keeps a copy of this vault with every account sealed: it never sees a "
          + "password, a key or what an account holds. It can see how many accounts there are, "
          + "roughly how big each is, and when they change. The enrollment secret is the one "
          + "your server was set up with; it is used once and not stored.")
      Text(
        "Each vault syncs on its own. To sync another vault through the same server, load it "
          + "(Settings ▸ Vault) and turn sync on there.")
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  // MARK: - On

  @ViewBuilder
  private func enabled(_ sync: SyncController, _ state: VaultRepository.SyncState) -> some View {
    let display = SyncStatusDisplay(sync.status, paused: sync.isPaused)
    Section("Sync") {
      LabeledContent("Status") {
        HStack {
          Image(systemName: display.symbol).foregroundStyle(display.tint)
          TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(display.title(now: context.date))
          }
        }
      }
      if let detail = display.detail {
        Text(detail).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if state.dirtyCount > 0 {
        LabeledContent("To upload", value: "\(state.dirtyCount)")
      }
      HStack {
        Spacer()
        Button("Sync Now") { Task { await sync.syncNow() } }
          .disabled(display.isSyncing)
      }
    }

    Section("This vault") {
      LabeledContent("Server") {
        Text(state.endpoint.absoluteString).textSelection(.enabled)
          .multilineTextAlignment(.trailing)
      }
      LabeledContent("Vault ID") {
        HStack(spacing: 4) {
          Text(state.vaultID.uuidString.lowercased())
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
          IconButton("Copy vault ID", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
              state.vaultID.uuidString.lowercased(), forType: .string)
          }
        }
      }
      LabeledContent("This Mac", value: sync.device.name)
      HStack {
        Spacer()
        Button("Add a Device…") {
          invite = SyncInvite(endpoint: state.endpoint, vaultID: state.vaultID)
        }
      }
      LabeledContent(
        "Sync on since",
        value: state.enabledAt.formatted(date: .abbreviated, time: .shortened))
    }

    DevicesList(sync: sync)

    Section {
      failure
      HStack {
        if working { ProgressView().controlSize(.small) }
        Spacer()
        Button("Turn Off Sync…") { confirmingOff = true }
          .disabled(working)
      }
    }
    .confirmationDialog(
      "Turn off sync for this vault?", isPresented: $confirmingOff, titleVisibility: .visible
    ) {
      Button("Turn Off, Keep the Server Copy") { Task { await disable(sync, delete: false) } }
      Button("Turn Off and Delete the Server Copy", role: .destructive) {
        Task { await disable(sync, delete: true) }
      }
    } message: {
      Text(
        "This Mac keeps every account either way. Deleting the server copy stops every other "
          + "device syncing this vault; they keep their own copies.")
    }
  }

  @ViewBuilder
  private var failure: some View {
    if let error {
      Label(error, systemImage: "xmark.octagon")
        .font(.callout).foregroundStyle(Palette.danger)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Actions

  private func enable(_ sync: SyncController) async {
    guard let endpoint = SyncEndpoint.parse(endpointText) else { return }
    working = true
    error = nil
    defer { working = false }
    do {
      try await sync.enable(endpoint: endpoint, enrollSecret: enrollSecret)
      SyncEndpoint.lastUsed = endpoint
      enrollSecret = ""
    } catch let failure as SyncError {
      error = failure.message
    } catch {
      self.error = String(describing: error)
    }
  }

  private func disable(_ sync: SyncController, delete: Bool) async {
    working = true
    error = nil
    defer { working = false }
    do {
      try await sync.disable(deleteServerCopy: delete)
    } catch let failure as SyncError {
      error = "Sync is still on. " + failure.message
    } catch {
      self.error = String(describing: error)
    }
  }
}
