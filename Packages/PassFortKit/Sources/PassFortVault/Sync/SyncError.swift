import Foundation

/// Every way a sync call can fail, as the engine needs to tell them apart (`m5-sync.md` A.11).
/// `HTTPSyncAPI` maps statuses and transport errors onto these; the UI's `SyncProblem` is built
/// from them later (Phase 13). No case carries a request or response body.
public enum SyncError: Error, Sendable, Equatable {
  // MARK: Configuration -- refused before any request is sent

  /// The endpoint is not `https`, and not plain `http` to a loopback host either. Sending
  /// `k_auth` there would put it on the wire in cleartext.
  case insecureEndpoint
  /// An `https` endpoint with an empty pin set: there is nothing to check the server against.
  case noPins

  // MARK: Transport

  /// No network, DNS failure, timeout, connection lost. Silent and retried (A.11).
  case offline
  /// The server's chain failed normal trust evaluation, or no certificate in it matched a pin.
  /// Sync stops; never "continue anyway".
  case pinningFailed
  /// A `3xx`. The API never redirects, so one is refused rather than followed -- a redirect
  /// could move the request to another host or scheme.
  case redirectRefused
  /// A success status whose body doesn't decode as the contract says.
  case invalidResponse

  // MARK: Statuses

  /// `400`: the server refused the request's shape -- a client bug.
  case badRequest
  /// `401`: wrong auth key, unknown vault, or a missing / expired / wrong-vault token.
  case unauthorized
  /// `403`: the enrollment secret is missing or wrong.
  case forbidden
  /// `404`: no such vault (`GET /header`) or device.
  case notFound
  /// `409` on create: a vault with this id already exists.
  case vaultExists
  /// `409` on push: these records moved on since their `baseVersion`; nothing was written.
  case conflicts([ConflictDTO])
  /// `409` on a header PUT: the server's header is at `headerVersion`, not our base.
  case headerConflict(headerVersion: UInt64)
  /// `410`: tombstones after the cursor were purged; resync from `since=0` (A.10).
  case resyncRequired
  /// `413`: a record or a batch over the size limits.
  case tooLarge
  /// `429`: locked out after failed sessions; try again after `retryAfter` seconds.
  case rateLimited(retryAfter: TimeInterval)
  /// `5xx` (or any status the contract doesn't name). `503` comes with `Retry-After`.
  case server(status: Int, retryAfter: TimeInterval?)
}
