import Foundation
import GRDB

/// File-level vault backup and restore (`docs/runbooks/m3-vault-management.md`).
///
/// Everything here works on the sealed file: no password, no key, no `PassFortCrypto`. A
/// backup is an ordinary single-file vault, so it carries exactly the exposure of the live
/// file (records are sealed per-record; the header holds salt and KDF parameters only).
///
/// The anti-rollback high-water mark is deliberately **not** part of a backup. Restoring an
/// older snapshot is what that mark exists to notice; the caller runs the existing
/// accept-restore step (`HighWaterMark.reset`) once the user has confirmed it was deliberate.
public enum VaultBackup {

  /// What a backup file says about itself, readable without the master password.
  public struct Info: Sendable, Equatable {
    public let vaultID: UUID
    public let vaultVersion: UInt64
    public let manifestMAC: Data
  }

  public enum Failure: Error, Equatable {
    /// The source or backup is missing, unreadable, corrupt, or not a PassFort vault.
    case notAVault
    /// A file already sits at the backup destination; backups are never overwritten.
    case destinationExists(String)
    /// The backup belongs to another vault than the one it would replace.
    case differentVault(backup: UUID, live: UUID)
  }

  // MARK: - Create

  /// Snapshot the vault at `databasePath` into a new single file at `destination`.
  ///
  /// The snapshot uses SQLite's online-backup API, which reads through the WAL -- copying
  /// `vault.sqlite` alone would miss everything not yet checkpointed. It is taken in a private
  /// local temp directory and only the main file is carried over, so a stray `-shm` never
  /// reaches `destination`. The file then lands beside `destination` under a temporary name and
  /// is renamed into place, so a half-written backup is never mistaken for a good one.
  ///
  /// - Throws: `Failure.destinationExists`, `Failure.notAVault`, or a file-system / SQLite error.
  @discardableResult
  public static func create(databasePath: String, to destination: URL) throws -> Info {
    let fm = FileManager.default
    let destinationPath = destination.path(percentEncoded: false)
    guard !fm.fileExists(atPath: destinationPath) else {
      throw Failure.destinationExists(destinationPath)
    }

    let scratch = fm.temporaryDirectory.appending(
      path: "passfort-backup-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fm.createDirectory(
      at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: scratch) }

    let snapshot = scratch.appending(path: "snapshot.sqlite")
    try writeSnapshot(of: databasePath, to: snapshot)
    guard let info = inspect(snapshot) else { throw Failure.notAVault }

    let staging = destination.deletingLastPathComponent()
      .appending(path: ".\(destination.lastPathComponent).partial")
    try? fm.removeItem(at: staging)  // left behind by an earlier crashed attempt
    try fm.copyItem(at: snapshot, to: staging)
    do {
      try fm.moveItem(at: staging, to: destination)
    } catch {
      try? fm.removeItem(at: staging)
      throw error
    }
    // Best effort: SMB/NFS shares often cannot hold POSIX modes.
    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationPath)
    return info
  }

  // MARK: - Inspect

  /// A cheap structural check, no password: opens read-only, runs `quick_check`, and requires
  /// the §5.3 header and the manifest row. `nil` means "not a usable PassFort vault".
  ///
  /// This proves the file is a vault, not that it is *the* vault -- the manifest MAC and the
  /// header are only verified by an unlock.
  public static func inspect(_ url: URL) -> Info? {
    let path = url.path(percentEncoded: false)
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    var config = Configuration()
    config.readonly = true
    guard let queue = try? DatabaseQueue(path: path, configuration: config) else { return nil }
    return try? queue.read { db in
      guard try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok" else { return nil }
      return try readInfo(db)
    }
  }

  // MARK: - Naming and retention

  /// `passfort-vault-<vault-uuid>-<UTC yyyyMMdd'T'HHmmss'Z'>.sqlite`. The UUID keeps several
  /// vaults apart in one folder; the timestamp makes names sort chronologically.
  public static func fileName(vaultID: UUID, at date: Date) -> String {
    "\(namePrefix(for: vaultID))\(timestamp(date)).sqlite"
  }

  /// The backups of `vaultID` in `folder`, newest first. Only names `fileName(vaultID:at:)` would
  /// have produced for that vault count, so other vaults' backups and unrelated files are ignored.
  /// Ordering is by name, not modification time: NAS clocks and `mtime`s are not trustworthy.
  /// A missing folder is not an error.
  public static func backups(in folder: URL, vaultID: UUID) throws -> [URL] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
    let prefix = namePrefix(for: vaultID)
    return try fm.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
      .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".sqlite") }
      .sorted(by: >)
      .map { folder.appending(path: $0) }
  }

  /// Delete all but the newest `keep` backups of `vaultID` in `folder` (at least one is always
  /// kept); see `backups(in:vaultID:)` for what counts as one.
  ///
  /// - Returns: the names removed.
  @discardableResult
  public static func prune(in folder: URL, vaultID: UUID, keep: Int) throws -> [String] {
    let doomed = try backups(in: folder, vaultID: vaultID).dropFirst(max(keep, 1))
    for url in doomed { try FileManager.default.removeItem(at: url) }
    return doomed.map(\.lastPathComponent)
  }

  // MARK: - Restore

  /// Replace the vault at `databasePath` with `backup`.
  ///
  /// The current files (`vault.sqlite` and its `-wal`/`-shm`) are **moved aside**, never
  /// deleted, as `vault.sqlite.pre-restore-<timestamp>` (+ `-wal`/`-shm`); the backup is then
  /// installed through a temporary name. The caller must have closed the live vault first, and
  /// should expect the next unlock to report a rollback until it runs accept-restore.
  ///
  /// - Parameter allowDifferentVault: restoring over a *different* vault is refused unless set.
  /// - Returns: where the previous main file went, or `nil` if there was no live vault.
  /// - Throws: `Failure.notAVault` (nothing is touched), `Failure.differentVault`.
  @discardableResult
  public static func restore(
    from backup: URL, toDatabasePath databasePath: String,
    allowDifferentVault: Bool = false, now: Date = .now
  ) throws -> URL? {
    guard let incoming = inspect(backup) else { throw Failure.notAVault }

    let fm = FileManager.default
    let live = URL(fileURLWithPath: databasePath)
    let current = inspect(live)
    if let current, current.vaultID != incoming.vaultID, !allowDifferentVault {
      throw Failure.differentVault(backup: incoming.vaultID, live: current.vaultID)
    }

    let parent = live.deletingLastPathComponent()
    if !fm.fileExists(atPath: parent.path(percentEncoded: false)) {
      try fm.createDirectory(
        at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    // Stage first: if the copy fails, the live vault has not been touched.
    let staging = URL(fileURLWithPath: databasePath + ".restoring")
    try? fm.removeItem(at: staging)
    try fm.copyItem(at: backup, to: staging)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path(percentEncoded: false))

    var movedAside: URL?
    let aside = databasePath + ".pre-restore-\(timestamp(now))"
    for suffix in ["", "-wal", "-shm"] {
      let source = databasePath + suffix
      guard fm.fileExists(atPath: source) else { continue }
      try fm.moveItem(atPath: source, toPath: aside + suffix)
      if suffix.isEmpty { movedAside = URL(fileURLWithPath: aside) }
    }
    try fm.moveItem(at: staging, to: live)
    return movedAside
  }

  // MARK: - Internals

  private static func writeSnapshot(of databasePath: String, to snapshot: URL) throws {
    guard FileManager.default.fileExists(atPath: databasePath) else { throw Failure.notAVault }
    var config = Configuration()
    config.readonly = true  // never creates a schema, never writes to the live file
    let source = try DatabaseQueue(path: databasePath, configuration: config)
    let copy = try DatabaseQueue(path: snapshot.path(percentEncoded: false))
    try source.backup(to: copy)
    // Back to a rollback journal, so the snapshot is one self-contained file.
    try copy.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA journal_mode = DELETE") }
  }

  private static func readInfo(_ db: Database) throws -> Info? {
    guard let header = try VaultMeta.read(db, .header),
      let vaultID = vaultID(inHeader: header),
      let mac = try VaultMeta.read(db, .manifestMAC)
    else { return nil }
    return Info(
      vaultID: vaultID, vaultVersion: try VaultMeta.readVaultVersion(db), manifestMAC: mac)
  }

  /// The one place Swift looks inside the header blob (§5.3, which C++ otherwise owns): magic
  /// `"PFV\x01"`, `format_version` (u16), then the 16-byte `vault_uuid`. Read-only and for
  /// naming / mismatch warnings; nothing here is authenticated, so a tampered value can at worst
  /// mislabel a file -- the unlock still verifies the header through the AEAD.
  static func vaultID(inHeader header: Data) -> UUID? {
    let magic: [UInt8] = [0x50, 0x46, 0x56, 0x01]
    let start = header.startIndex + magic.count + 2
    guard header.count >= magic.count + 2 + 16, header.prefix(magic.count).elementsEqual(magic)
    else { return nil }
    return Array(header[start..<start + 16]).withUnsafeBytes {
      UUID(uuid: $0.loadUnaligned(as: uuid_t.self))
    }
  }

  private static func namePrefix(for vaultID: UUID) -> String {
    "passfort-vault-\(vaultID.uuidString.lowercased())-"
  }

  private static func timestamp(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(
      format: "%04d%02d%02dT%02d%02d%02dZ",
      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
  }
}
