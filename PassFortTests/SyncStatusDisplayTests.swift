import Foundation
import PassFortVault
import Testing

@testable import PassFort

/// The sidebar footer's wording for each sync status (`m5-sync.md` A.11).
@MainActor
struct SyncStatusDisplayTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func idleSaysWhenItLastSynced() {
    #expect(SyncStatusDisplay(.idle(lastSyncedAt: now), paused: false).title(now: now)
      == "Synced just now")
    #expect(SyncStatusDisplay(.idle(lastSyncedAt: nil), paused: false).title(now: now)
      == "Not synced yet")
  }

  @Test func offlineIsQuietAndNotAProblem() {
    let display = SyncStatusDisplay(.offline, paused: false)
    #expect(display.title(now: now) == "Offline")
    #expect(display.kind == .offline)
  }

  @Test func aServerErrorWaitsButAPausedProblemIsAProblem() {
    let server = SyncStatusDisplay(.problem(.server(status: 503, retryAfter: 1)), paused: false)
    #expect(server.kind == .waiting)
    #expect(server.title(now: now) == "Sync will retry")

    let pinning = SyncStatusDisplay(.problem(.pinningFailed), paused: true)
    #expect(pinning.kind == .problem)
    #expect(pinning.title(now: now) == "Sync problem")
    #expect(pinning.detail == SyncError.pinningFailed.message)
  }

  @Test func syncingDisablesSyncNow() {
    #expect(SyncStatusDisplay(.syncing(.pulling), paused: false).isSyncing)
    #expect(!SyncStatusDisplay(.offline, paused: false).isSyncing)
  }

  @Test func everyHardProblemPausesAndNeverRetriesByItself() {
    let hard: [SyncError] = [
      .unauthorized, .serverRollback, .tamperedRecord(UUID()), .pinningFailed, .noPins,
    ]
    for error in hard {
      #expect(error.pausesSync)
      #expect(!error.retriesByItself)
    }
    #expect(!SyncError.offline.pausesSync)
    #expect(!SyncError.server(status: 500, retryAfter: nil).pausesSync)
  }
}
