import ArgumentParser
import Foundation
import PassFortCrypto
import PassFortVault

#if canImport(Glibc)
  import Glibc
#endif

struct CLIError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

/// This install's device (`m5-sync.md` A.5): `~/.config/passfort/device.json`, created on first
/// use -- the CLI's own, separate from the app's (which lives in its sandbox container). It
/// stamps every write's HLC and names this device to the sync server.
///
/// `PASSFORT_DEVICE_FILE` points every command at another identity file, so two CLI "devices"
/// can share one machine (the Phase 11 drill). Every command, not just `sync`: the id stamps
/// each `add` and `edit` too.
enum CLIDevice {
  static let fileVariable = "PASSFORT_DEVICE_FILE"

  static var url: URL {
    if let path = ProcessInfo.processInfo.environment[fileVariable], !path.isEmpty {
      return URL(fileURLWithPath: path)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appending(
      path: ".config/passfort/device.json")
  }

  static func identity() throws -> DeviceIdentity {
    do {
      return try DeviceIdentity.loadOrCreate(at: url, name: "\(DeviceIdentity.hostName) (CLI)")
    } catch {
      throw CLIError(
        "can't read or create the device identity at \(url.path(percentEncoded: false)): \(error)")
    }
  }

  static func id() throws -> UUID { try identity().id }
}

// MARK: - Opening a vault

enum VaultCLI {
  /// Prompt for the password and open the SQLite vault at `path`, translating the
  /// storage / crypto failures into `CLIError`s with actionable messages. The
  /// manifest MAC and anti-rollback checks (§5.5) run in here, inside
  /// `Vault.unlock`.
  static func open(
    _ path: String, prompt message: String = "Vault password: "
  ) async throws -> VaultRepository {
    guard FileManager.default.fileExists(atPath: path) else {
      throw CLIError("no vault at \(path) -- create one with `passfort-cli init \(path)`")
    }
    let password = try Password.prompt(message)
    do {
      let repo = try await Vault.unlock(
        databasePath: path, password: password, deviceID: try CLIDevice.id())
      if try await repo.headerChangedElsewhere() {
        FileHandle.standardError.write(
          Data(
            """
            note: the master password or recovery key was changed on another device. Unlock with \
            the new password to finish updating this vault.

            """.utf8))
      }
      return repo
    } catch PassFortError.authFailed {
      throw CLIError("AuthFailed -- wrong password or corrupt vault")
    } catch VaultError.notFound {
      throw CLIError("\(path) is not a PassFort vault (no header row)")
    } catch let failure as VaultManifest.Failure {
      throw CLIError(Self.describe(failure, path: path))
    }
  }

  private static func describe(_ failure: VaultManifest.Failure, path: String) -> String {
    switch failure {
    case .macMismatch:
      return """
        manifest MAC mismatch -- a record was added, removed, or edited outside PassFort. \
        The vault is not safe to use.
        """
    case .rollbackDetected(let version, let highWater):
      return """
        rollback detected -- the file is at vault_version \(version) but this machine last \
        saw \(highWater). A restored backup and an attacker rolling the file back look the \
        same from inside the file. If you deliberately restored a backup, run:

            passfort-cli verify --vault \(path) --accept-restore
        """
    }
  }
}

// MARK: - Naming an account

/// Resolve an account reference to its id (`matchAccount`). Titles and id prefixes match live
/// accounts, or only deleted ones with `deleted`. Several matches go to `AccountPicker`.
func resolveAccountID(
  _ reference: String, in repo: VaultRepository, deleted: Bool = false
) async throws -> UUID {
  if let uuid = UUID(uuidString: reference) { return uuid }

  // Live accounts, or only the deleted ones when `deleted` is set (for `undelete`).
  let pool = try await repo.summaries().filter { $0.isDeleted == deleted }
  switch matchAccount(reference, in: pool) {
  case .one(let id): return id
  case .none: throw CLIError("no account matches \"\(reference)\"")
  case .several(let rows): return try AccountPicker.choose(from: rows, for: reference)
  }
}

enum AccountMatch: Equatable {
  case one(UUID)
  case none
  case several([AccountSummary])
}

/// What `reference` names in `pool`: a full id; else a title, an exact (case-insensitive) match
/// first; else every account whose title contains it or whose id starts with it. An id prefix
/// needs at least `minimumIDPrefix` hex digits, so a short word isn't read as one.
func matchAccount(_ reference: String, in pool: [AccountSummary]) -> AccountMatch {
  if let uuid = UUID(uuidString: reference) { return .one(uuid) }

  let exact = pool.filter { $0.title.caseInsensitiveCompare(reference) == .orderedSame }
  if exact.count == 1 { return .one(exact[0].id) }
  if exact.count > 1 { return .several(exact) }

  let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
  let idPrefix =
    reference.count >= minimumIDPrefix && reference.unicodeScalars.allSatisfy(hex.contains)
    ? reference.lowercased() : nil
  let partial = pool.filter { row in
    row.title.range(of: reference, options: .caseInsensitive) != nil
      || idPrefix.map { row.id.uuidString.lowercased().hasPrefix($0) } ?? false
  }
  switch partial.count {
  case 0: return .none
  case 1: return .one(partial[0].id)
  default: return .several(partial)
  }
}

let minimumIDPrefix = 4

/// The shortest id prefixes, at least 8 characters, that still tell `ids` apart -- what `list`
/// prints, lowercase, and what a reference may use instead of the whole id.
func shortIDs(_ ids: [UUID]) -> [UUID: String] {
  let full = Dictionary(ids.map { ($0, $0.uuidString.lowercased()) }) { first, _ in first }
  var width = 8
  while width < 36, Set(full.values.map { $0.prefix(width) }).count < full.count {
    width += 1
  }
  return full.mapValues { String($0.prefix(width)) }
}

/// A reference that matches several accounts. At a terminal, offer them as a numbered list;
/// otherwise (a pipe, a script) fail and say how to narrow it.
enum AccountPicker {
  /// More than this and the reference is too vague to be worth a menu.
  static let limit = 20

  static func choose(from rows: [AccountSummary], for reference: String) throws -> UUID {
    let rows = rows.sorted {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    guard isatty(STDIN_FILENO) == 1, isatty(STDERR_FILENO) == 1, rows.count <= limit else {
      throw CLIError(
        "\"\(reference)\" matches \(rows.count) accounts -- narrow it, or use the id from `list`")
    }
    FileHandle.standardError.write(Data(menu(rows, for: reference).utf8))
    guard let line = readLine(strippingNewline: true),
      let choice = Int(line.trimmingCharacters(in: .whitespaces)),
      rows.indices.contains(choice - 1)
    else {
      throw CLIError("no account chosen")
    }
    return rows[choice - 1].id
  }

  /// The numbered list and the question, for rows already in display order.
  static func menu(_ rows: [AccountSummary], for reference: String) -> String {
    let ids = shortIDs(rows.map(\.id))
    var text = "\"\(reference)\" matches \(rows.count) accounts:\n"
    for (index, row) in rows.enumerated() {
      let details = [row.username, row.host].compactMap { $0 }.joined(separator: "  ")
      text += "  \(index + 1)) \(row.title)\(details.isEmpty ? "" : "  \(details)")"
      text += "  [\(ids[row.id] ?? "")]\n"
    }
    return text + "Which one? [1-\(rows.count)]: "
  }
}

// MARK: - Parsing helpers

func parseURL(_ raw: String) throws -> URL {
  guard let url = URL(string: raw) else { throw CLIError("not a valid URL: \(raw)") }
  return url
}

func parseCategory(_ raw: String) throws -> AccountCategory {
  guard let category = AccountCategory(rawValue: raw) else {
    let known = AccountCategory.allCases.map(\.rawValue).joined(separator: ", ")
    throw CLIError("unknown category \"\(raw)\" -- one of: \(known)")
  }
  return category
}

// MARK: - Password generation

/// Shared flags for the random password generator -- composed into `gen`, `add`,
/// and `edit` via `@OptionGroup`.
struct PasswordGenOptions: ParsableArguments {
  @Option(help: "Generated password length (1-1024).") var length: Int = 20
  @Flag(name: .customLong("no-lowercase"), help: "Exclude a-z.") var noLowercase = false
  @Flag(name: .customLong("no-uppercase"), help: "Exclude A-Z.") var noUppercase = false
  @Flag(name: .customLong("no-digits"), help: "Exclude 0-9.") var noDigits = false
  @Flag(name: .customLong("no-symbols"), help: "Exclude punctuation.") var noSymbols = false
  @Flag(name: .customLong("allow-ambiguous"), help: "Allow the look-alikes 0 O 1 l I.")
  var allowAmbiguous = false

  var policy: PasswordPolicy {
    PasswordPolicy(
      length: length,
      lowercase: !noLowercase, uppercase: !noUppercase, digits: !noDigits, symbols: !noSymbols,
      excludeAmbiguous: !allowAmbiguous,
      // Only require a class we're actually including.
      minLowercase: noLowercase ? 0 : 1, minUppercase: noUppercase ? 0 : 1,
      minDigits: noDigits ? 0 : 1, minSymbols: noSymbols ? 0 : 1)
  }
}

/// `gen --words`: a passphrase from the EFF large word list instead of random characters.
struct PassphraseGenOptions: ParsableArguments {
  @Option(help: "Generate a passphrase of this many words (1-64) instead of a password.")
  var words: Int?
  @Option(help: "Put between passphrase words (with --words).") var separator: String = "-"
  @Flag(help: "Capitalize each passphrase word (with --words).") var capitalize = false
  @Flag(help: "Append a digit to one passphrase word (with --words).") var digit = false

  /// `nil` without `--words`; a `CLIError` for a word count out of range.
  var policy: PassphrasePolicy? {
    get throws {
      guard let words else { return nil }
      guard (1...64).contains(words) else { throw CLIError("--words must be between 1 and 64") }
      return PassphrasePolicy(
        wordCount: words, separator: separator, capitalize: capitalize, includeDigit: digit)
    }
  }
}

/// Generate a password, turning a `PasswordPolicy.Failure` into a `CLIError`.
func generatedPassword(from policy: PasswordPolicy) throws -> String {
  do { return try policy.generate() } catch { throw CLIError(describePolicyFailure(error)) }
}

func passwordEntropyBits(_ policy: PasswordPolicy) throws -> Int {
  do {
    return Int(try policy.entropyBits().rounded())
  } catch {
    throw CLIError(describePolicyFailure(error))
  }
}

private func describePolicyFailure(_ error: Error) -> String {
  switch error {
  case PasswordPolicy.Failure.noCharacterClasses:
    return "every character class is disabled -- drop one of the --no-* flags"
  case PasswordPolicy.Failure.emptyAlphabet:
    return "a character class has no usable characters (empty symbol set, or all filtered out)"
  case PasswordPolicy.Failure.lengthTooShortForMinimums:
    return "--length is too short to fit one character from each enabled class"
  case PasswordPolicy.Failure.invalidLength:
    return "--length must be between 1 and 1024"
  default:
    return "invalid password policy: \(error)"
  }
}

func parseBool(_ raw: String) throws -> Bool {
  switch raw.lowercased() {
  case "true", "yes", "y", "1", "on": return true
  case "false", "no", "n", "0", "off": return false
  default: throw CLIError("not a boolean: \"\(raw)\" (use true / false)")
  }
}

/// An `otpauth://totp/...` URI or a bare Base32 secret, as `--totp` / `--set totp=` take it.
func parseTOTP(_ raw: String) throws -> TOTPConfig {
  do {
    return try TOTPConfig(parsing: raw)
  } catch {
    throw CLIError("not an otpauth://totp URI or a Base32 secret (\(error))")
  }
}

/// One `--set key=value` edit. Parsed (and validated) up front so a bad key or
/// value fails before the write transaction opens.
enum EditOp: Sendable {
  enum Field: String { case title, username, password, email, notes, favorite, category, totp }
  case set(Field, String)

  static func parse(_ pair: String) throws -> EditOp {
    guard let equals = pair.firstIndex(of: "=") else {
      throw CLIError("--set needs key=value, got \"\(pair)\"")
    }
    let rawKey = String(pair[..<equals])
    let value = String(pair[pair.index(after: equals)...])
    guard let field = Field(rawValue: rawKey) else {
      throw CLIError(
        "unknown --set key \"\(rawKey)\" -- one of: "
          + "title, username, password, email, notes, favorite, category, totp")
    }
    if field == .title, value.isEmpty { throw CLIError("title cannot be empty") }
    if field == .favorite { _ = try parseBool(value) }
    if field == .category { _ = try parseCategory(value) }
    if field == .totp, !value.isEmpty { _ = try parseTOTP(value) }
    return .set(field, value)
  }

  func apply(to payload: inout AccountPayload) {
    guard case .set(let field, let value) = self else { return }
    let optional = value.isEmpty ? nil : value
    switch field {
    case .title: payload.title = value
    case .username: payload.username = optional
    case .password: payload.password = optional
    case .email: payload.email = optional
    case .notes: payload.notes = optional
    case .favorite: payload.favorite = (try? parseBool(value)) ?? payload.favorite
    case .category: payload.category = (try? parseCategory(value)) ?? payload.category
    case .totp: payload.totp = value.isEmpty ? nil : (try? parseTOTP(value)) ?? payload.totp
    }
  }
}

// MARK: - Output

func prettyJSON(_ value: some Encodable) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  encoder.dateEncodingStrategy = .iso8601
  return try encoder.encode(value)
}

/// The envelope identity + last-write time wrapped around the decrypted payload
/// -- what `get --json` and `dump` emit (the shape `export` already uses).
struct AccountJSON: Encodable {
  let id: UUID
  let version: UInt64
  let updatedAt: Date
  let isDeleted: Bool
  let payload: AccountPayload

  enum CodingKeys: String, CodingKey {
    case id, version, payload
    case updatedAt = "updated_at"
    case isDeleted = "is_deleted"
  }

  init(_ account: Account) {
    id = account.id
    version = account.version
    updatedAt = account.lastUpdated
    isDeleted = account.isDeleted
    payload = account.payload
  }
}

/// `rows` by title, each under its short id from `ids` (`shortIDs`).
func printSummaryTable(_ rows: [AccountSummary], ids: [UUID: String]) {
  guard !rows.isEmpty else {
    print("(no matching accounts)")
    return
  }
  let sorted = rows.sorted {
    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
  }
  func pad(_ string: String, _ width: Int) -> String {
    string.count >= width ? string : string + String(repeating: " ", count: width - string.count)
  }
  let idWidth = ids.values.map(\.count).max() ?? 8
  print("\(pad("ID", idWidth))  \(pad("TITLE", 24))  \(pad("USERNAME", 20))  HOST")
  for row in sorted {
    let id = ids[row.id] ?? row.id.uuidString.lowercased()
    var line = "\(pad(id, idWidth))  \(pad(String(row.title.prefix(24)), 24))  "
    line += "\(pad(row.username ?? "-", 20))  \(row.host ?? "-")"
    var flags: [String] = []
    if row.favorite { flags.append("fav") }
    if row.isConflict { flags.append("conflict") }
    if row.isDeleted { flags.append("deleted") }
    if !flags.isEmpty { line += "  [\(flags.joined(separator: ","))]" }
    print(line)
  }
}

/// One account for `get`. The password, PIN, memorable word and recovery codes show only with
/// `reveal`, so a plain `get` leaves no secret in the scrollback (§3.4).
func printAccount(_ account: Account, reveal: Bool) {
  let payload = account.payload
  func row(_ label: String, _ value: String?) {
    guard let value, !value.isEmpty else { return }
    print("\(label.padding(toLength: 15, withPad: " ", startingAt: 0))\(value)")
  }
  func secret(_ label: String, _ value: String?) {
    row(label, reveal ? value : value.map { _ in "(hidden -- `copy` it, or pass --reveal)" })
  }
  let iso = ISO8601DateFormatter()

  row("id", account.id.uuidString)
  row("version", String(account.version))
  if account.isDeleted { row("status", "DELETED (tombstone)") }
  row("title", payload.title)
  row("username", payload.username)
  secret("password", payload.password)
  row("email", payload.email)
  if !payload.urls.isEmpty {
    row("urls", payload.urls.map(\.absoluteString).joined(separator: ", "))
  }
  row("notes", payload.notes)
  row("category", payload.category.rawValue)
  if payload.favorite { row("favorite", "yes") }
  if !payload.tags.isEmpty { row("tags", payload.tags.joined(separator: ", ")) }
  secret("pin", payload.pin)
  secret("memorable", payload.memorableWord)
  if !payload.recoveryCodes.isEmpty {
    secret("recovery codes", payload.recoveryCodes.joined(separator: ", "))
  }
  if let totp = payload.totp {
    row("totp", "\(totp.code()) (\(totp.secondsRemaining())s left; `export` for the seed)")
  }
  if !payload.securityQuestions.isEmpty {
    row("sec questions", String(payload.securityQuestions.count))
  }
  row("created", iso.string(from: payload.createdAt))
  row("updated", iso.string(from: account.lastUpdated))
  if let changed = payload.passwordChangedAt {
    row("pw changed", iso.string(from: changed))
  }
  if let latest = payload.revisionHistory.first {
    row(
      "revisions",
      "\(payload.revisionHistory.count) "
        + "(latest v\(latest.version): \(latest.changed.joined(separator: ", ")))")
  }
  if !payload.passwordHistory.isEmpty {
    row(
      "old passwords",
      "\(payload.passwordHistory.count) kept -- `passfort-cli history … --passwords` to read")
  }
  if let expiresAt = payload.expiresAt { row("expires", iso.string(from: expiresAt)) }
}

/// The one-time recovery key, printed to stderr (a piped stdout stays clean),
/// wrapped in a hard-to-miss banner.
enum RecoveryBanner {
  static func show(_ key: RecoveryKey) {
    let rule = String(repeating: "=", count: 64)
    FileHandle.standardError.write(
      Data(
        """

        \(rule)
        RECOVERY KEY -- write it down now and store it offline. Shown once.
        It unlocks this vault without the master password; anyone who has it
        can open the vault.

            \(key.grouped)

        \(rule)

        """.utf8))
  }
}

// MARK: - Passwords

enum Password {
  /// Read a line from the controlling terminal with echo off. The password never
  /// touches the screen, the scrollback, `ps`, or the shell history (which a
  /// `--password` flag would not avoid). getpass(3) uses a static buffer; we copy
  /// it out and scrub it.
  static func prompt(_ message: String) throws -> Data {
    guard let raw = getpass(message) else {
      throw CLIError("could not read a password from the terminal")
    }
    let count = strlen(raw)
    let data = Data(bytes: raw, count: count)
    raw.withMemoryRebound(to: UInt8.self, capacity: count) { p in
      for i in 0..<count { p[i] = 0 }
    }
    return data
  }

  /// Prompt twice and require a match -- for vault creation, where a typo means a
  /// permanently unopenable vault.
  static func promptConfirmed() throws -> Data {
    let first = try prompt("New vault password: ")
    let second = try prompt("Repeat password: ")
    guard first == second else { throw CLIError("passwords did not match") }
    guard !first.isEmpty else { throw CLIError("password must not be empty") }
    return first
  }
}

// MARK: - Files

enum Files {
  static func read(_ path: String) throws -> Data {
    do {
      return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw CLIError("cannot read \(path): \(error.localizedDescription)")
    }
  }

  static func writeNew(_ data: Data, to path: String, force: Bool) throws {
    let url = URL(fileURLWithPath: path)
    if !force, FileManager.default.fileExists(atPath: path) {
      throw CLIError("\(path) already exists (pass --force to overwrite)")
    }
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw CLIError("cannot write \(path): \(error.localizedDescription)")
    }
  }

  /// Write to `path`, or to stdout when `path` is nil.
  static func emit(_ data: Data, to path: String?) throws {
    if let path {
      try writeNew(data, to: path, force: true)
    } else {
      FileHandle.standardOutput.write(data)
    }
  }

  /// Write a new `0600` file, refusing to clobber. For plaintext exports and any
  /// other secret output.
  static func writeSecret(_ data: Data, to path: String) throws {
    try writeNew(data, to: path, force: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
  }

  /// Remove a vault file and its sidecars (`-wal`, `-shm`, `.hw`) -- `init --force`.
  static func removeVault(at path: String) {
    for suffix in ["", "-wal", "-shm", ".hw"] {
      try? FileManager.default.removeItem(atPath: path + suffix)
    }
  }
}
