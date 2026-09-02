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
      Add.self, List.self, Get.self, History.self, Edit.self, Remove.self,
      Dump.self, Export.self, Recover.self, Seam.self,
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
    abstract: "Generate random password(s). No vault needed; prints to stdout.")

  @OptionGroup var options: PasswordGenOptions
  @Option(name: [.short, .long], help: "How many to generate.") var count: Int = 1

  func run() throws {
    guard count >= 1 else { throw CLIError("--count must be at least 1") }
    let policy = options.policy
    let bits = try passwordEntropyBits(policy)
    FileHandle.standardError.write(Data("~\(bits) bits of entropy each\n".utf8))
    for _ in 0..<count {
      print(try generatedPassword(from: policy))
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

    let repo = try await VaultCLI.open(vault)
    let account = try await repo.create(
      AccountPayload(
        title: title, username: username, password: secret, email: email,
        urls: parsedURLs, notes: note, category: cat, tags: tags, favorite: favorite))
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
      password, email, notes, favorite, category.
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
