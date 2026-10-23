import ArgumentParser
import Foundation
import PassFortCrypto
import PassFortVault

@main
struct PassFortCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "passfort-cli",
    abstract: "PassFort vault tool -- create an encrypted SQLite vault and manage accounts in it.",
    subcommands: [
      Bench.self, Gen.self, Init.self, Unlock.self, Verify.self,
      Add.self, List.self, Get.self, Code.self, History.self, Edit.self, Remove.self,
      Undelete.self, Audit.self, Import.self, ImportVault.self,
      Dump.self, Export.self, Backup.self, Restore.self, Recover.self, Passwd.self, Seam.self,
    ]
  )
}

// MARK: - bench

struct Bench: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Calibrate Argon2id for this machine and print the parameters.")

  @Option(help: "Target unlock time in milliseconds.") var targetMs: UInt32 = 500

  func run() throws {
    let clock = ContinuousClock()
    var params = KdfParameters(kdfID: 0, memoryKiB: 0, iterations: 0, parallelism: 0, salt: Data())
    let calibration = try clock.measure {
      params = try VaultSession.calibrate(targetMs: targetMs)
    }

    let header = try VaultSession.create(password: Data("bench".utf8), params: params)
    let oneHash = try clock.measure {
      _ = try VaultSession.open(header: header, password: Data("bench".utf8))
    }

    print("kdf          argon2id")
    print("memory       \(params.memoryKiB) KiB (\(params.memoryKiB / 1024) MiB)")
    print("iterations   \(params.iterations)")
    print("parallelism  \(params.parallelism)")
    print("calibration  \(calibration)")
    print("one unlock   \(oneHash)")
  }
}

// MARK: - gen

struct Gen: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Generate random password(s) or passphrase(s). No vault needed; prints to stdout.")

  @OptionGroup var options: PasswordGenOptions
  @OptionGroup var passphrase: PassphraseGenOptions
  @Option(name: [.short, .long], help: "How many to generate.") var count: Int = 1

  func run() throws {
    guard count >= 1 else { throw CLIError("--count must be at least 1") }
    let next: () throws -> String
    let bits: Int
    if let policy = try passphrase.policy {
      bits = Int(try policy.entropyBits().rounded())
      next = { try policy.generate() }
    } else {
      let policy = options.policy
      bits = try passwordEntropyBits(policy)
      next = { try generatedPassword(from: policy) }
    }
    FileHandle.standardError.write(Data("~\(bits) bits of entropy each\n".utf8))
    for _ in 0..<count {
      print(try next())
    }
  }
}

// MARK: - init

struct Init: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Create a new vault (an encrypted SQLite database) and prompt for its password.")

  @Argument(help: "Path to the vault file to create.") var vault: String
  @Option(help: "Argon2id calibration target in milliseconds.") var targetMs: UInt32 = 500
  @Flag(help: "Also generate a recovery key -- a second way in, shown once (§5.6).")
  var recovery = false
  @Flag(help: "Delete an existing vault (and its sidecars) at this path first.") var force = false

  func run() async throws {
    if force { Files.removeVault(at: vault) }
    guard !FileManager.default.fileExists(atPath: vault) else {
      throw CLIError("\(vault) already exists (pass --force to replace it)")
    }
    let password = try Password.promptConfirmed()

    FileHandle.standardError.write(Data("calibrating Argon2id (~\(targetMs) ms)...\n".utf8))
    let params = try VaultSession.calibrate(targetMs: targetMs)

    if recovery {
      let (_, key) = try await Vault.createWithRecovery(
        databasePath: vault, password: password, params: params, deviceID: m2DeviceID)
      RecoveryBanner.show(key)
    } else {
      _ = try await Vault.create(
        databasePath: vault, password: password, params: params, deviceID: m2DeviceID)
    }
    let extra = recovery ? ", + recovery key" : ""
    print("created \(vault) (\(params.memoryKiB / 1024) MiB Argon2id\(extra))")
  }
}

// MARK: - unlock

struct Unlock: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Open a vault, run the manifest + anti-rollback checks, report what's inside.")

  @Argument(help: "Path to the vault file.") var vault: String

  func run() async throws {
    let repo = try await VaultCLI.open(vault)
    let summaries = try await repo.summaries()
    let live = summaries.filter { !$0.isDeleted }.count
    let tombstones = summaries.count - live
    let tail = tombstones > 0 ? ", \(tombstones) tombstoned" : ""
    print("unlocked OK -- \(live) account\(live == 1 ? "" : "s")\(tail)")
  }
}

// MARK: - verify

struct Verify: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check the manifest MAC and the anti-rollback mark, nothing else.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Flag(help: "Accept a deliberately restored backup: clear the anti-rollback mark first.")
  var acceptRestore = false

  func run() async throws {
    if acceptRestore {
      try HighWaterMark(sidecarFor: vault).reset()
      FileHandle.standardError.write(Data("anti-rollback mark cleared; re-verifying...\n".utf8))
    }
    _ = try await VaultCLI.open(vault)
    print("verify OK -- manifest and vault_version consistent")
  }
}

// MARK: - add

struct Add: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Create an account in the vault. Prints its id.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Option(help: "Account title (required).") var title: String
  @Option(help: "Username.") var username: String?
  @Option(help: "Email.") var email: String?
  @Option(help: "Password value (ends up in shell history -- prefer --prompt-password).")
  var password: String?
  @Flag(help: "Prompt for the account password with no echo.") var promptPassword = false
  @Flag(help: "Generate a random password (shaped by the generation options); printed to stderr.")
  var generatePassword = false
  @OptionGroup(title: "Password generation (with --generate-password)")
  var passwordGen: PasswordGenOptions
  @Option(name: .customLong("url"), help: "A URL for the account (repeatable).")
  var urls: [String] = []
  @Option(help: "Free-text note.") var note: String?
  @Option(help: "Category (default: login).") var category: String?
  @Option(name: .customLong("tag"), help: "A tag (repeatable).") var tags: [String] = []
  @Flag(help: "Mark as a favorite.") var favorite = false
  @Option(help: "One-time-code secret: an otpauth://totp/... URI or a Base32 secret.")
  var totp: String?

  func run() async throws {
    let sources = [password != nil, promptPassword, generatePassword].filter { $0 }.count
    guard sources <= 1 else {
      throw CLIError("choose one of --password, --prompt-password, --generate-password")
    }
    let secret: String?
    if generatePassword {
      let generated = try generatedPassword(from: passwordGen.policy)
      FileHandle.standardError.write(Data("generated password: \(generated)\n".utf8))
      secret = generated
    } else if promptPassword {
      secret = String(decoding: try Password.prompt("Account password: "), as: UTF8.self)
    } else {
      secret = password
    }
    let parsedURLs = try urls.map(parseURL)
    let cat = try category.map(parseCategory) ?? .login
    let otp = try totp.map(parseTOTP)

    let repo = try await VaultCLI.open(vault)
    let account = try await repo.create(
      AccountPayload(
        title: title, username: username, password: secret, email: email,
        urls: parsedURLs, notes: note, totp: otp, category: cat, tags: tags, favorite: favorite))
    print(account.id.uuidString)
  }
}

// MARK: - list

struct List: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List accounts from the in-memory summary index -- no secrets.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Option(
    name: .shortAndLong,
    help: "Case-insensitive substring filter on title / username / host / tag.")
  var search: String?
  @Flag(help: "Include tombstoned (deleted) accounts.") var all = false

  func run() async throws {
    let repo = try await VaultCLI.open(vault)
    var rows = try await repo.summaries()
    if !all { rows = rows.filter { !$0.isDeleted } }
    if let query = search?.lowercased(), !query.isEmpty {
      rows = rows.filter { row in
        row.title.lowercased().contains(query)
          || (row.username?.lowercased().contains(query) ?? false)
          || (row.host?.lowercased().contains(query) ?? false)
          || row.tags.contains { $0.lowercased().contains(query) }
      }
    }
    printSummaryTable(rows)
  }
}

// MARK: - get

struct Get: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show one account -- secrets included -- on stdout.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Argument(help: "Account id (UUID) or title.") var account: String
  @Flag(help: "Emit the decrypted payload as JSON.") var json = false

  func run() async throws {
    let repo = try await VaultCLI.open(vault)
    let id = try await resolveAccountID(account, in: repo)
    guard let account = try await repo.account(id: id) else {
      throw CLIError("no account with id \(id.uuidString)")
    }
    if json {
      FileHandle.standardOutput.write(try prettyJSON(AccountJSON(account)))
      FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
      printAccount(account)
    }
  }
}

// MARK: - code

struct Code: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Print an account's current one-time code (TOTP) and how long it stays valid.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Argument(help: "Account id (UUID) or title.") var account: String

  func run() async throws {
    let repo = try await VaultCLI.open(vault)
    let id = try await resolveAccountID(account, in: repo)
    guard let account = try await repo.account(id: id) else {
      throw CLIError("no account with id \(id.uuidString)")
    }
    guard let totp = account.payload.totp else {
      throw CLIError(
        "\(account.payload.title) has no one-time code -- add one with `edit --set totp=...`")
    }
    let now = Date()
    print(totp.code(at: now))
    FileHandle.standardError.write(Data("valid for \(totp.secondsRemaining(at: now))s\n".utf8))
  }
}

// MARK: - history

struct History: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show an account's version timeline -- what changed, when.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Argument(help: "Account id (UUID) or title.") var account: String
  @Flag(help: "Also print the old password values (secrets, like `get`).") var passwords = false

  func run() async throws {
    let repo = try await VaultCLI.open(vault)
    let id = try await resolveAccountID(account, in: repo)
    guard let account = try await repo.account(id: id) else {
      throw CLIError("no account with id \(id.uuidString)")
    }
    let payload = account.payload
    let iso = ISO8601DateFormatter()

    let deleted = account.isDeleted ? ", tombstoned" : ""
    print("\(payload.title)  (\(account.id.uuidString), currently v\(account.version)\(deleted))")

    if payload.revisionHistory.isEmpty {
      print("  no recorded revisions")
    } else {
      for entry in payload.revisionHistory {
        print(
          "  v\(entry.version)  \(iso.string(from: entry.at))  "
            + entry.changed.joined(separator: ", "))
      }
      if payload.revisionHistory.count >= VaultRepository.revisionHistoryLimit {
        let cap = VaultRepository.revisionHistoryLimit
        print("  (older revisions dropped -- the last \(cap) are kept)")
      }
    }

    guard !payload.passwordHistory.isEmpty else { return }
    print("\nprevious passwords (\(payload.passwordHistory.count)):")
    for old in payload.passwordHistory {
      let value = passwords ? old.password : "(hidden -- pass --passwords)"
      print("  \(iso.string(from: old.replacedAt))  \(value)")
    }
  }
}

// MARK: - edit

struct Edit: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: """
      Update an account. Repeatable --set key=value; keys: title, username, \
      password, email, notes, favorite, category, totp (an otpauth:// URI or \
      Base32 secret; empty clears it).
      """)

  @Argument(help: "Path to the vault file.") var vault: String
  @Argument(help: "Account id (UUID) or title.") var account: String
  @Option(name: .customLong("set"), help: "key=value (repeatable).") var sets: [String] = []
  @Flag(help: "Prompt for a new account password with no echo.") var promptPassword = false
  @Flag(help: "Set the password to a fresh random one (see generation options); printed to stderr.")
  var generatePassword = false
  @OptionGroup(title: "Password generation (with --generate-password)")
  var passwordGen: PasswordGenOptions
  @Option(name: .customLong("add-url"), help: "Append a URL (repeatable).")
  var addURLs: [String] = []

  func run() async throws {
    let setsPassword = sets.contains { $0.hasPrefix("password=") }
    let passwordSources = [setsPassword, promptPassword, generatePassword].filter { $0 }.count
    guard passwordSources <= 1 else {
      throw CLIError(
        "set the password one way: --set password=..., --prompt-password, or --generate-password")
    }

    var parsed = try sets.map(EditOp.parse)
    if promptPassword {
      let entered = String(decoding: try Password.prompt("New account password: "), as: UTF8.self)
      parsed.append(.set(.password, entered))
    }
    if generatePassword {
      let generated = try generatedPassword(from: passwordGen.policy)
      FileHandle.standardError.write(Data("generated password: \(generated)\n".utf8))
      parsed.append(.set(.password, generated))
    }
    let ops = parsed
    let appended = try addURLs.map(parseURL)
    guard !ops.isEmpty || !appended.isEmpty else {
      throw CLIError(
        "nothing to change -- pass --set, --add-url, --prompt-password, or --generate-password")
    }

    let repo = try await VaultCLI.open(vault)
    let id = try await resolveAccountID(account, in: repo)
    let updated = try await repo.update(id: id) { payload in
      for op in ops { op.apply(to: &payload) }
      payload.urls.append(contentsOf: appended)
    }
    print("updated \(updated.id.uuidString) -> version \(updated.version)")
  }
}

// MARK: - rm

struct Remove: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "rm",
    abstract: "Tombstone an account. The row survives until `compact` (M5).")

  @Argument(help: "Path to the vault file.") var vault: String
  @Argument(help: "Account id (UUID) or title.") var account: String

  func run() async throws {
    let repo = try await VaultCLI.open(vault)
    let id = try await resolveAccountID(account, in: repo)
    try await repo.delete(id: id)
    print("tombstoned \(id.uuidString)")
  }
}

// MARK: - undelete

struct Undelete: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Bring back a deleted (tombstoned) account as a new version.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Argument(help: "Deleted account's id (UUID) or title -- see `list --all`.") var account: String

  func run() async throws {
    let repo = try await VaultCLI.open(vault)
    let id = try await resolveAccountID(account, in: repo, deleted: true)
    do {
      let restored = try await repo.restore(id: id)
      print("restored \(restored.id.uuidString) -> version \(restored.version)")
    } catch VaultError.notFound {
      throw CLIError("no deleted account with id \(id.uuidString)")
    }
  }
}

// MARK: - audit

struct Audit: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Password health: weak, reused, old, expiring and http:// accounts. No secrets shown."
  )

  @Argument(help: "Path to the vault file.") var vault: String

  func run() async throws {
    let repo = try await VaultCLI.open(vault)
    let findings = try await repo.audit()
    let titles = Dictionary(
      uniqueKeysWithValues: try await repo.summaries().map { ($0.id, $0.title) })
    guard !findings.isEmpty else {
      print("no findings -- nothing weak, reused, old, expiring or on http://")
      return
    }
    for finding in findings {
      let title = titles[finding.account] ?? finding.account.uuidString
      print(
        "\(describe(finding.kind).padding(toLength: 34, withPad: " ", startingAt: 0))  \(title)")
    }
    print("\(findings.count) finding\(findings.count == 1 ? "" : "s")")
  }

  private func describe(_ kind: AuditFinding.Kind) -> String {
    let day = Date.FormatStyle(date: .abbreviated, time: .omitted)
    switch kind {
    case .weak(let score): return "weak (score \(score)/4)"
    case .reused(let count): return "reused (\(count) accounts)"
    case .old(let since): return "old (unchanged since \(since.formatted(day)))"
    case .expired(let on): return "expired \(on.formatted(day))"
    case .expiringSoon(let on): return "expires \(on.formatted(day))"
    case .insecureURL: return "http:// login URL"
    }
  }
}

// MARK: - import

struct Import: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract:
      "Import a Password Safe plain-text export (tab-separated). Prints titles, never secrets.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Argument(help: "The Password Safe export (File > Export To > Plain Text).") var file: String
  @Flag(help: "Show what would be imported; write nothing.") var dryRun = false
  @Flag(help: "Import accounts that look like ones already in the vault, too.")
  var includeDuplicates = false

  func run() async throws {
    let plan: ImportPlan
    do {
      plan = try PasswordSafeImport.plan(try Files.read(file))
    } catch PasswordSafeImport.Failure.notPasswordSafeExport {
      throw CLIError(
        "\(file) has no Group/Title header -- not a tab-separated Password Safe export")
    } catch PasswordSafeImport.Failure.notText {
      throw CLIError("\(file) is not UTF-8 text")
    }

    let repo = try await VaultCLI.open(vault)
    let duplicates = plan.duplicates(of: try await repo.summaries())
    let chosen = plan.accounts.indices.filter { includeDuplicates || !duplicates.contains($0) }

    for index in plan.accounts.indices {
      let payload = plan.accounts[index].payload
      let mark = chosen.contains(index) ? "+" : "="
      let extras = [payload.totp != nil ? "one-time code" : nil, payload.tags.first]
        .compactMap { $0 }.joined(separator: ", ")
      print("\(mark) \(payload.title)\(extras.isEmpty ? "" : "  (\(extras))")")
    }
    for skip in plan.skipped { print("! line \(skip.line) skipped: \(skip.reason)") }
    for warning in plan.warnings { print("! \(warning)") }
    for (column, rows) in plan.ignoredColumns.sorted(by: { $0.key < $1.key }) {
      print(
        "! column \"\(column)\" not imported (had a value in \(rows) row\(rows == 1 ? "" : "s"))")
    }

    let skippedDuplicates = plan.accounts.count - chosen.count
    let summary =
      "\(chosen.count) to import, \(skippedDuplicates) duplicate\(skippedDuplicates == 1 ? "" : "s") "
      + "skipped (=), \(plan.skipped.count) unreadable row\(plan.skipped.count == 1 ? "" : "s")"
    if dryRun {
      print("dry run -- \(summary)")
      return
    }
    let written = try await repo.importAccounts(chosen.map { plan.accounts[$0].payload })
    print("imported \(written) -- \(summary)")
    print("the export file holds every password in plain text: delete it now")
  }
}

// MARK: - import-vault

struct ImportVault: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "import-vault",
    abstract:
      "Copy accounts from another PassFort vault into this one (§7.6). Prints titles, never secrets."
  )

  @Argument(help: "Path to the vault to import into.") var vault: String
  @Argument(help: "Path to the vault to copy from. Opened read-only.") var source: String
  @Option(
    help: ArgumentHelp(
      "Import only accounts whose title contains this (case-insensitive). Repeatable.",
      valueName: "title"))
  var only: [String] = []
  @Option(help: "Unlock the source with its grouped recovery key instead of its password.")
  var recoveryKey: String?
  @Flag(help: "Show what would be imported; write nothing.") var dryRun = false
  @Flag(help: "Import accounts that look like ones already in the vault, too.")
  var includeDuplicates = false

  func run() async throws {
    guard Vault.exists(databasePath: source) else {
      throw CLIError("\(source) is not a PassFort vault")
    }
    var key: RecoveryKey?
    if let recoveryKey {
      do {
        key = try RecoveryKey(grouped: recoveryKey)
      } catch {
        throw CLIError("that does not parse as a recovery key (\(error))")
      }
    }

    let repo = try await VaultCLI.open(vault)
    let credential: VaultImport.Credential =
      if let key { .recoveryKey(key) } else {
        .password(try Password.prompt("Source vault password: "))
      }
    let plan = try await plan(credential: credential, into: repo)

    let titles = plan.accounts.map(\.payload.title)
    func matches(_ title: String, _ filter: String) -> Bool {
      title.range(of: filter, options: .caseInsensitive) != nil
    }
    for filter in only where !titles.contains(where: { matches($0, filter) }) {
      throw CLIError("--only \"\(filter)\" matches no account in \(source)")
    }
    let selected = titles.indices.filter { i in
      only.isEmpty || only.contains { matches(titles[i], $0) }
    }
    let duplicates = plan.duplicates(of: try await repo.summaries())
    let chosen = selected.filter { includeDuplicates || !duplicates.contains($0) }

    for index in plan.accounts.indices {
      let payload = plan.accounts[index].payload
      let mark = chosen.contains(index) ? "+" : selected.contains(index) ? "=" : "-"
      let extras = [payload.totp != nil ? "one-time code" : nil, payload.tags.first]
        .compactMap { $0 }.joined(separator: ", ")
      print("\(mark) \(payload.title)\(extras.isEmpty ? "" : "  (\(extras))")")
    }
    for warning in plan.warnings { print("! \(warning)") }

    let skippedDuplicates = selected.count - chosen.count
    let unselected = plan.accounts.count - selected.count
    var summary =
      "\(chosen.count) to import, \(skippedDuplicates) duplicate\(skippedDuplicates == 1 ? "" : "s") "
      + "skipped (=)"
    if !only.isEmpty { summary += ", \(unselected) not selected (-)" }
    if dryRun {
      print("dry run -- \(summary)")
      return
    }
    let written = try await repo.importAccounts(chosen.map { plan.accounts[$0].payload })
    print("imported \(written) -- \(summary)")
  }

  private func plan(
    credential: VaultImport.Credential, into repo: VaultRepository
  ) async throws -> ImportPlan {
    do {
      return try await VaultImport.plan(
        fromVaultAt: source, unlockingWith: credential, into: repo)
    } catch PassFortError.authFailed {
      throw CLIError(
        "AuthFailed -- wrong password or recovery key for \(source), or a corrupt vault")
    } catch PassFortError.notFound {
      throw CLIError("\(source) has no recovery slot -- unlock it with its password")
    } catch VaultImport.Failure.notAVault {
      throw CLIError("\(source) is not a PassFort vault (no header row)")
    } catch VaultImport.Failure.sameVault {
      throw CLIError("\(source) is \(vault) itself, or a copy of it -- nothing to import")
    } catch VaultImport.Failure.unsupportedSchema {
      throw CLIError(
        """
        \(source) is on a different schema than this build. If it is older, upgrade it first \
        with `passfort-cli unlock \(source)`; if it is newer, update passfort-cli.
        """)
    } catch VaultManifest.Failure.macMismatch {
      throw CLIError(
        "manifest MAC mismatch -- \(source) was edited outside PassFort; not importing from it")
    }
  }
}

// MARK: - dump

struct Dump: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Print every record (tombstones included), decrypted, as JSON. Debug aid.")

  @Argument(help: "Path to the vault file.") var vault: String

  func run() async throws {
    let repo = try await VaultCLI.open(vault)
    var entries: [AccountJSON] = []
    for summary in try await repo.summaries() {
      guard let account = try await repo.account(id: summary.id) else { continue }
      entries.append(AccountJSON(account))
    }
    FileHandle.standardError.write(
      Data("dumping \(entries.count) record(s) -- plaintext secrets follow\n".utf8))
    FileHandle.standardOutput.write(try prettyJSON(entries))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}

// MARK: - export

struct Export: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Decrypt the whole vault to a plaintext JSON file (§7.6), behind a typed phrase.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Option(name: .shortAndLong, help: "Output file. Created 0600; must not already exist.")
  var output: String

  func run() async throws {
    FileHandle.standardError.write(
      Data(
        """
        This writes every password in the clear to \(output).
        Type "\(ExportConfirmation.phrase)" to continue:
        """.utf8))
    guard let line = readLine(strippingNewline: true) else { throw CLIError("no input") }
    let confirmation: ExportConfirmation
    do {
      confirmation = try ExportConfirmation(phrase: line)
    } catch {
      throw CLIError("confirmation phrase did not match -- nothing exported")
    }

    let repo = try await VaultCLI.open(vault)
    let export = try await repo.exportPlaintext(confirmed: confirmation)
    try Files.writeSecret(try export.jsonData(), to: output)
    let done =
      "wrote \(export.accounts.count) account(s) to \(output) (mode 0600). "
      + "Delete it when you are done.\n"
    FileHandle.standardError.write(Data(done.utf8))
  }
}

// MARK: - backup

struct Backup: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Write a consistent single-file snapshot of the vault into a folder (no password).",
    discussion: """
      The snapshot is taken through SQLite's backup API, so records still in the write-ahead \
      log are included. The file is named passfort-vault-<vault-uuid>-<UTC time>.sqlite and is \
      as sensitive as the vault itself: sealed records plus the plaintext header.
      """)

  @Argument(help: "Path to the vault file.") var vault: String
  @Argument(help: "Folder to write the backup into (created if missing).") var folder: String
  @Option(help: "Afterwards, keep only the newest N backups of this vault in the folder.")
  var keep: Int?

  func run() async throws {
    guard let live = VaultBackup.inspect(URL(fileURLWithPath: vault)) else {
      throw CLIError("\(vault) is not a PassFort vault")
    }
    let directory = URL(fileURLWithPath: folder, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let destination = directory.appending(
      path: VaultBackup.fileName(vaultID: live.vaultID, at: .now))
    do {
      let info = try VaultBackup.create(databasePath: vault, to: destination)
      print("backup written: \(destination.path(percentEncoded: false))")
      print("vault_version \(info.vaultVersion)")
    } catch VaultBackup.Failure.destinationExists {
      throw CLIError("a backup with this timestamp already exists -- wait a second and retry")
    }

    if let keep {
      let removed = try VaultBackup.prune(in: directory, vaultID: live.vaultID, keep: keep)
      if !removed.isEmpty {
        FileHandle.standardError.write(Data("pruned \(removed.count) older backup(s)\n".utf8))
      }
    }
  }
}

// MARK: - restore

struct Restore: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Replace the vault with a backup. The current vault is moved aside, not deleted.",
    discussion: """
      Close every app using the vault first. The previous files are kept next to it as \
      vault.sqlite.pre-restore-<time>. The anti-rollback mark is left alone, so the next unlock \
      reports a rollback; confirm it was deliberate with `verify <vault> --accept-restore`.
      """)

  @Argument(help: "Path to the backup file.") var backup: String
  @Argument(help: "Path to the vault file to replace.") var vault: String
  @Flag(help: "Allow replacing a vault with a backup of a different vault.")
  var allowDifferentVault = false
  @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

  func run() async throws {
    guard let incoming = VaultBackup.inspect(URL(fileURLWithPath: backup)) else {
      throw CLIError("\(backup) is not a usable PassFort vault backup")
    }
    let current = VaultBackup.inspect(URL(fileURLWithPath: vault))

    if !yes {
      let replacing = current.map { "vault_version \($0.vaultVersion)" } ?? "(no vault there)"
      FileHandle.standardError.write(
        Data(
          """
          Restore vault_version \(incoming.vaultVersion) over \(replacing) at \(vault).
          Changes made after the backup will be lost from the active vault.
          Type "yes" to continue:
          """.utf8))
      guard readLine(strippingNewline: true) == "yes" else {
        throw CLIError("not confirmed -- nothing changed")
      }
    }

    do {
      let aside = try VaultBackup.restore(
        from: URL(fileURLWithPath: backup), toDatabasePath: vault,
        allowDifferentVault: allowDifferentVault)
      if let aside { print("previous vault kept at: \(aside.path(percentEncoded: false))") }
      print("restored. Next: passfort-cli verify \(vault) --accept-restore")
    } catch VaultBackup.Failure.differentVault {
      throw CLIError(
        "the backup belongs to a different vault than \(vault) -- pass --allow-different-vault if that is intended"
      )
    }
  }
}

// MARK: - recover

struct Recover: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Open the vault with its recovery key and set a new master password (§5.6).")

  @Argument(help: "Path to the vault file.") var vault: String
  @Option(name: .customLong("key"), help: "The grouped recovery key, as written down.")
  var key: String

  func run() async throws {
    guard FileManager.default.fileExists(atPath: vault) else {
      throw CLIError("no vault at \(vault)")
    }
    let recoveryKey: RecoveryKey
    do {
      recoveryKey = try RecoveryKey(grouped: key)
    } catch {
      throw CLIError("that does not parse as a recovery key (\(error))")
    }

    let newPassword = try Password.promptConfirmed()
    let repo: VaultRepository
    do {
      repo = try await Vault.recover(
        databasePath: vault, recoveryKey: recoveryKey, newPassword: newPassword,
        deviceID: m2DeviceID)
    } catch PassFortError.authFailed {
      throw CLIError("recovery key rejected -- wrong key")
    } catch PassFortError.notFound {
      throw CLIError("this vault has no recovery slot")
    }

    // The recovery slot is consumed by `recover`; issue a fresh one.
    let fresh = try await repo.rotateRecoveryKey()
    print("recovered \(vault) -- master password reset.")
    RecoveryBanner.show(fresh)
  }
}

// MARK: - passwd

struct Passwd: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Change the master password. Any existing recovery key stops working.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Flag(help: "Leave the vault password-only instead of issuing a new recovery key.")
  var noRecoveryKey = false

  func run() async throws {
    guard FileManager.default.fileExists(atPath: vault) else {
      throw CLIError("no vault at \(vault)")
    }
    // Unlocked here rather than through `VaultCLI.open`: the same bytes are needed
    // again as `current` for the change itself.
    let current = try Password.prompt("Current vault password: ")
    let repo: VaultRepository
    do {
      repo = try await Vault.unlock(databasePath: vault, password: current, deviceID: m2DeviceID)
    } catch PassFortError.authFailed {
      throw CLIError("AuthFailed -- wrong password or corrupt vault")
    }
    let new = try Password.promptConfirmed()
    let fresh = try await repo.changePassword(
      current: current, new: new, issueRecoveryKey: !noRecoveryKey)
    print("master password changed for \(vault).")
    print("backups made before now still open with the old password.")
    if let fresh { RecoveryBanner.show(fresh) }
  }
}

// MARK: - seam (M0 + M1 smoke test)

struct Seam: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Run the M0 + M1 seam round trip end to end.")

  func run() async throws {
    let probe = Data("passfort seam check".utf8)
    guard try echo(probe) == probe else { throw CLIError("seam round-trip MISMATCH") }
    print("seam OK -- \(probe.count) bytes round-tripped through C++")
    print("botan \(try botanVersion())")

    let password = Data("test".utf8)
    let params = try VaultSession.calibrate(targetMs: 1)
    let header = try VaultSession.create(password: password, params: params)
    let session = try VaultSession.open(header: header, password: password)

    let recordID = UUID()
    let secret = Data("hunter2".utf8)
    let sealed = try await session.seal(
      recordID: recordID, version: 1, schema: 1, plaintext: secret)
    let recovered = try await session.open(
      recordID: recordID, version: 1, schema: 1, sealed: sealed)
    guard recovered == secret else { throw CLIError("seal/open round trip mismatch") }

    do {
      _ = try await session.open(recordID: UUID(), version: 1, schema: 1, sealed: sealed)
      throw CLIError("expected AuthFailed for a mismatched record id")
    } catch PassFortError.authFailed {}

    print("M1 seam OK")
  }
}
