import PassFortVault
import SwiftUI

/// The sidebar footer's sync line (`m5-sync.md` A.11): an icon and "Synced 2 min ago" /
/// "Syncing…" / "Offline" / "Sync problem". Clicking it opens the detail and Sync Now. Shows
/// nothing while sync is off.
struct SyncStatusFooter: View {
  @Environment(AppModel.self) private var model
  @State private var showingDetail = false

  var body: some View {
    if let sync = model.sync, sync.state != nil {
      let display = SyncStatusDisplay(sync.status, paused: sync.isPaused)
      Button {
        showingDetail.toggle()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: display.symbol).foregroundStyle(display.tint)
          TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(display.title(now: context.date)).lineLimit(1)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .help("Sync status")
      .popover(isPresented: $showingDetail, arrowEdge: .top) {
        SyncStatusDetail(sync: sync, headerChangedElsewhere: model.headerChangedElsewhere)
      }
    }
  }
}

/// The popover: what the last run did or what stopped it, and Sync Now.
private struct SyncStatusDetail: View {
  let sync: SyncController
  let headerChangedElsewhere: Bool

  var body: some View {
    let display = SyncStatusDisplay(sync.status, paused: sync.isPaused)
    VStack(alignment: .leading, spacing: 10) {
      Label {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          Text(display.title(now: context.date)).font(.headline)
        }
      } icon: {
        Image(systemName: display.symbol).foregroundStyle(display.tint)
      }

      if let detail = display.detail {
        Text(detail).font(.callout).fixedSize(horizontal: false, vertical: true)
      }
      if headerChangedElsewhere {
        Text(SyncError.headerChangedElsewhere.message)
          .font(.callout).foregroundStyle(Palette.warning)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let state = sync.state {
        if state.dirtyCount > 0 {
          Text("\(state.dirtyCount) change\(state.dirtyCount == 1 ? "" : "s") to upload")
            .font(.caption).foregroundStyle(.secondary)
        }
        Text(state.endpoint.host() ?? state.endpoint.absoluteString)
          .font(.caption).foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      HStack {
        Spacer()
        Button("Sync Now") { Task { await sync.syncNow() } }
          .disabled(display.isSyncing)
      }
    }
    .padding(14)
    .frame(width: 280)
  }
}

/// How a `SyncStatus` reads in the footer: pure, so it is tested without a view.
struct SyncStatusDisplay: Equatable {
  enum Kind: Equatable {
    case synced(Date?)
    case syncing
    case offline
    case waiting
    case problem
  }

  let kind: Kind
  /// The sentence under the title in the popover, if there is more to say.
  let detail: String?

  init(_ status: SyncStatus, paused: Bool) {
    switch status {
    case .off, .idle(nil):
      kind = .synced(nil)
      detail = nil
    case .idle(let date?):
      kind = .synced(date)
      detail = nil
    case .syncing:
      kind = .syncing
      detail = nil
    case .offline:
      kind = .offline
      detail = "PassFort will sync when the server can be reached again."
    case .problem(let error):
      // Retried on their own: a busy or failing server, a rate limit, a race with another device.
      kind = paused || !error.retriesByItself ? .problem : .waiting
      detail = error.message
    }
  }

  var isSyncing: Bool { kind == .syncing }

  func title(now: Date) -> String {
    switch kind {
    case .synced(let date?):
      let elapsed = now.timeIntervalSince(date)
      if elapsed < 60 { return "Synced just now" }
      return "Synced \(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
    case .synced(nil): return "Not synced yet"
    case .syncing: return "Syncing…"
    case .offline: return "Offline"
    case .waiting: return "Sync will retry"
    case .problem: return "Sync problem"
    }
  }

  var symbol: String {
    switch kind {
    case .synced: "arrow.triangle.2.circlepath"
    case .syncing: "arrow.triangle.2.circlepath"
    case .offline: "wifi.slash"
    case .waiting: "clock.arrow.circlepath"
    case .problem: "exclamationmark.triangle"
    }
  }

  var tint: Color {
    switch kind {
    case .synced, .syncing, .offline: .secondary
    case .waiting: Palette.warning
    case .problem: Palette.danger
    }
  }
}
