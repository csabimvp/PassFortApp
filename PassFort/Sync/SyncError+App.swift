import PassFortVault

// How the app reads a `SyncError` (`m5-sync.md` A.11): whether it pauses sync, whether the next
// run is likely to clear it, and the sentence shown for it.

extension SyncError {
  /// A problem the next automatic run won't fix: sync pauses until the user acts (A.11).
  var pausesSync: Bool {
    switch self {
    case .unauthorized, .forbidden, .notFound, .serverRollback, .tamperedRecord, .pinningFailed,
      .insecureEndpoint, .noPins, .redirectRefused, .invalidResponse, .badRequest, .tooLarge:
      true
    case .offline, .rateLimited, .server, .conflicts, .resyncRequired, .vaultExists,
      .headerConflict, .headerChangedElsewhere, .notEnabled:
      false
    }
  }

  /// The next automatic run may well succeed: nothing to do but wait.
  var retriesByItself: Bool {
    switch self {
    case .server, .rateLimited, .conflicts, .resyncRequired, .offline: true
    default: false
    }
  }

  /// One plain sentence for the footer, a sheet or an alert. Never carries a body or a key.
  var message: String {
    switch self {
    case .insecureEndpoint:
      "PassFort only syncs over https. Plain http is allowed for localhost only."
    case .noPins:
      "This copy of PassFort has no certificate pins, so it can't check the server."
    case .offline: "The sync server can't be reached."
    case .pinningFailed:
      "The server's certificate doesn't match the pins this copy of PassFort trusts. Sync is "
        + "paused. Update PassFort; never bypass the check."
    case .redirectRefused: "The server answered with a redirect, which PassFort refuses."
    case .invalidResponse: "The server's answer doesn't match what PassFort expects."
    case .badRequest: "The server refused a request as malformed."
    case .unauthorized:
      "The server doesn't accept this vault's key. It may have been recreated. Turn sync off and "
        + "on again."
    case .forbidden: "That enrollment secret is wrong."
    case .notFound: "The server has no such vault. Check the vault id, or whether it was deleted."
    case .vaultExists: "This vault already syncs."
    case .conflicts: "Other devices kept changing the same accounts. PassFort will try again."
    case .headerConflict, .headerChangedElsewhere:
      "The master password or recovery key was changed on another device. Unlock with the new "
        + "password to finish updating this Mac."
    case .resyncRequired: "The server needs a full resync. PassFort will do one."
    case .tooLarge: "An account is too large to sync. Shorten its notes or history."
    case .server(status: 405, _):
      "That address isn't a PassFort sync server's API. It should end in /\(SyncEndpoint.apiRoot)."
    case .rateLimited(let after):
      "The server asked PassFort to wait \(Int(after.rounded(.up))) seconds."
    case .server(let status, _): "The sync server had an error (\(status)). PassFort will retry."
    case .notEnabled: "Sync is off for this vault."
    case .serverRollback:
      "The server has less than this Mac already received: it was rolled back or replaced. Sync "
        + "is paused, and nothing was changed here."
    case .tamperedRecord:
      "An account from the server failed its integrity check, so nothing from that batch was "
        + "applied. If this happens again, treat the server as compromised."
    }
  }
}
