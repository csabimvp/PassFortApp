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

/// M2 is single-device; `records.updated_at` persists only the HLC wall-clock
/// millis, so the device id is a fixed zero UUID (it matches `SealedRecord`'s M2
/// constant). M5 sync gives each install a real one.
let m2DeviceID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

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
      return try await Vault.unlock(databasePath: path, password: password, deviceID: m2DeviceID)
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

            passfort-cli verify \(path) --accept-restore
        """
    }
  }
}

/// Resolve an account reference -- a UUID string, or a (case-insensitive) title,
/// exact match first then a unique substring -- to its id.
func resolveAccountID(_ reference: String, in repo: VaultRepository) async throws -> UUID {
  if let uuid = UUID(uuidString: reference) { return uuid }

  let live = try await repo.summaries().filter { !$0.isDeleted }
  let exact = live.filter { $0.title.caseInsensitiveCompare(reference) == .orderedSame }
  if exact.count == 1 { return exact[0].id }
  if exact.count > 1 {
    throw CLIError("\(exact.count) accounts are titled \"\(reference)\" -- pass the id instead")
  }

  let partial = live.filter { $0.title.range(of: reference, options: .caseInsensitive) != nil }
  switch partial.count {
  case 1: return partial[0].id
  case 0: throw CLIError("no account matches \"\(reference)\"")
  default:
    throw CLIError("\"\(reference)\" matches \(partial.count) accounts -- narrow it or pass the id")
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

/// One `--set key=value` edit. Parsed (and validated) up front so a bad key or
/// value fails before the write transaction opens.
enum EditOp: Sendable {
  enum Field: String { case title, username, password, email, notes, favorite, category }
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
          + "title, username, password, email, notes, favorite, category")
    }
    if field == .title, value.isEmpty { throw CLIError("title cannot be empty") }
    if field == .favorite { _ = try parseBool(value) }
    if field == .category { _ = try parseCategory(value) }
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

func printSummaryTable(_ rows: [AccountSummary]) {
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
  print("\(pad("ID", 36))  \(pad("TITLE", 24))  \(pad("USERNAME", 20))  HOST")
  for row in sorted {
    var line = "\(pad(row.id.uuidString, 36))  \(pad(String(row.title.prefix(24)), 24))  "
    line += "\(pad(row.username ?? "-", 20))  \(row.host ?? "-")"
    var flags: [String] = []
    if row.favorite { flags.append("fav") }
    if row.isConflict { flags.append("conflict") }
    if row.isDeleted { flags.append("deleted") }
    if !flags.isEmpty { line += "  [\(flags.joined(separator: ","))]" }
    print(line)
  }
}

func printAccount(_ account: Account) {
  let payload = account.payload
  func row(_ label: String, _ value: String?) {
    guard let value, !value.isEmpty else { return }
    print("\(label.padding(toLength: 15, withPad: " ", startingAt: 0))\(value)")
  }
  let iso = ISO8601DateFormatter()

  row("id", account.id.uuidString)
  row("version", String(account.version))
  if account.isDeleted { row("status", "DELETED (tombstone)") }
  row("title", payload.title)
  row("username", payload.username)
  row("password", payload.password)
  row("email", payload.email)
  if !payload.urls.isEmpty {
    row("urls", payload.urls.map(\.absoluteString).joined(separator: ", "))
  }
  row("notes", payload.notes)
  row("category", payload.category.rawValue)
  if payload.favorite { row("favorite", "yes") }
  if !payload.tags.isEmpty { row("tags", payload.tags.joined(separator: ", ")) }
  row("pin", payload.pin)
  row("memorable", payload.memorableWord)
  if !payload.recoveryCodes.isEmpty {
    row("recovery codes", payload.recoveryCodes.joined(separator: ", "))
  }
  if payload.totp != nil { row("totp", "configured (use `export` for the seed)") }
  if !payload.securityQuestions.isEmpty {
    row("sec questions", String(payload.securityQuestions.count))
  }
  row("created", iso.string(from: payload.createdAt))
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
