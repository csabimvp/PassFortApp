import ArgumentParser
import Foundation
import PassFortVault

// MARK: - The config file

/// The vaults this CLI remembers: `~/.config/passfort/config.json`, next to `device.json` and
/// `pins`. Names and paths only -- never a password, a key, or anything from inside a vault.
///
/// `PASSFORT_CONFIG` points every command at another file, as `PASSFORT_DEVICE_FILE` does for the
/// device identity, so the drill and the tests never touch the real one.
struct CLIConfig: Codable, Equatable {
  static let fileVariable = "PASSFORT_CONFIG"
  static let vaultVariable = "PASSFORT_VAULT"

  /// Name -> absolute path.
  var vaults: [String: String] = [:]
  /// One of `vaults`' names: the vault a command opens when nothing else names one.
  var defaultVault: String?

  enum CodingKeys: String, CodingKey {
    case vaults
    case defaultVault = "default"
  }

  init(vaults: [String: String] = [:], defaultVault: String? = nil) {
    self.vaults = vaults
    self.defaultVault = defaultVault
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    vaults = try container.decodeIfPresent([String: String].self, forKey: .vaults) ?? [:]
    defaultVault = try container.decodeIfPresent(String.self, forKey: .defaultVault)
  }

  static var url: URL {
    if let path = ProcessInfo.processInfo.environment[fileVariable], !path.isEmpty {
      return URL(fileURLWithPath: path)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appending(
      path: ".config/passfort/config.json")
  }

  /// The config at `url`, or an empty one if there is no file yet.
  static func load(from url: URL = url) throws -> CLIConfig {
    let path = url.path(percentEncoded: false)
    guard FileManager.default.fileExists(atPath: path) else { return CLIConfig() }
    do {
      return try JSONDecoder().decode(CLIConfig.self, from: Data(contentsOf: url))
    } catch {
      throw CLIError("can't read \(path): \(error) -- fix it, or delete it to start over")
    }
  }

  /// Write the config (`0600`, directory `0700`, like `device.json`).
  func save(to url: URL = url) throws {
    let path = url.path(percentEncoded: false)
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(self).write(to: url, options: [.atomic])
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    } catch {
      throw CLIError("can't write \(path): \(error.localizedDescription)")
    }
  }

  // MARK: Resolving

  /// What `--vault` or `PASSFORT_VAULT` refers to: a registered name, else a path. A name wins,
  /// so with a vault named `work` registered, `./work` reaches a file of that name.
  func path(for reference: String) -> String {
    vaults[reference] ?? Self.absolute(reference)
  }

  /// The vault a command acts on: `--vault`, else `PASSFORT_VAULT`, else the default vault.
  func resolve(_ flag: String?, environment: [String: String]) throws -> String {
    if let flag, !flag.isEmpty { return path(for: flag) }
    if let variable = environment[Self.vaultVariable], !variable.isEmpty {
      return path(for: variable)
    }
    if let name = defaultVault, let path = vaults[name] { return path }
    throw CLIError(
      """
      which vault? Pass --vault <name|path>, set \(Self.vaultVariable), or remember one with
          passfort-cli vault add <name> <path>
      """)
  }

  /// `path` made absolute against the working directory, with a leading `~` expanded.
  static func absolute(_ path: String) -> String {
    let expanded = NSString(string: path).expandingTildeInPath
    return URL(fileURLWithPath: expanded).standardizedFileURL.path(percentEncoded: false)
  }

  // MARK: Registering

  /// A vault name: letters, digits, `.`, `_` and `-`, not starting with `-` (it would read as a
  /// flag). No `/`, so a name never looks like a path.
  static func validate(name: String) throws {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    guard !name.isEmpty, !name.hasPrefix("-"),
      name.unicodeScalars.allSatisfy(allowed.contains)
    else {
      throw CLIError(
        "\"\(name)\" can't be a vault name -- use letters, digits, '.', '_' and '-'")
    }
  }

  /// Check `name` is free before `init` or `sync join` creates anything.
  func checkAvailable(_ name: String) throws {
    try Self.validate(name: name)
    if let taken = vaults[name] {
      throw CLIError("\"\(name)\" already names \(taken) -- pick another, or `vault forget` it")
    }
  }

  /// Remember the vault `init` or `sync join` just made at `path`: under `name` if given, else,
  /// when there is no default vault yet, under the file's name. The first vault remembered
  /// becomes the default. Returns a line saying what happened.
  mutating func registerNew(at path: String, as name: String?) -> String {
    let path = Self.absolute(path)
    let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let candidate = name ?? (defaultVault == nil ? stem : nil)
    guard let chosen = candidate, (try? checkAvailable(chosen)) != nil else {
      return "use it by name with: passfort-cli vault add <name> \(path)"
    }
    vaults[chosen] = path
    if defaultVault == nil {
      defaultVault = chosen
      return "remembered as \"\(chosen)\", the default vault"
    }
    return "remembered as \"\(chosen)\" -- pick it with --vault \(chosen)"
  }

  /// Shell completion for `--vault`: the remembered names.
  @Sendable static func completionNames(_: [String], _: Int, _: String) -> [String] {
    ((try? load())?.vaults.keys).map { $0.sorted() } ?? []
  }
}

// MARK: - --vault

/// `--vault`, on every command that opens an existing vault.
struct VaultOption: ParsableArguments {
  @Option(
    name: [.customShort("v"), .long],
    help: ArgumentHelp(
      "A vault name from `vault list`, or a path. Default: $PASSFORT_VAULT, else the default vault.",
      valueName: "name|path"),
    completion: .custom(CLIConfig.completionNames))
  var vault: String?

  /// The path of the vault this command acts on.
  func path() throws -> String {
    try CLIConfig.load().resolve(vault, environment: ProcessInfo.processInfo.environment)
  }
}

// MARK: - vault

struct VaultCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "vault",
    abstract: "Remember vaults by name and pick the default one, so commands need no path.",
    discussion: """
      A command acts on --vault (a name or a path), else on $\(CLIConfig.vaultVariable), else on \
      the default vault. The names live in ~/.config/passfort/config.json -- paths only, nothing \
      secret. `init` and `sync join` remember the first vault they create. Set \
      \(CLIConfig.fileVariable) to use another config file.
      """,
    subcommands: [VaultList.self, VaultAdd.self, VaultUse.self, VaultForget.self],
    defaultSubcommand: VaultList.self)
}

struct VaultList: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "Show the remembered vaults; * marks the default.")

  func run() async throws {
    let config = try CLIConfig.load()
    guard !config.vaults.isEmpty else {
      print("no vaults remembered -- passfort-cli vault add <name> <path>")
      return
    }
    let width = config.vaults.keys.map(\.count).max() ?? 0
    for (name, path) in config.vaults.sorted(by: { $0.key < $1.key }) {
      let mark = name == config.defaultVault ? "*" : " "
      let missing = FileManager.default.fileExists(atPath: path) ? "" : "  (missing)"
      let padded = name.padding(toLength: width, withPad: " ", startingAt: 0)
      print("\(mark) \(padded)  \(path)\(missing)")
    }
    if let variable = ProcessInfo.processInfo.environment[CLIConfig.vaultVariable],
      !variable.isEmpty
    {
      print("\(CLIConfig.vaultVariable) is set: commands use \(config.path(for: variable))")
    }
  }
}

struct VaultAdd: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add",
    abstract: "Remember an existing vault file under a name. The first one becomes the default.")

  @Argument(help: "The name to use with --vault.") var name: String
  @Argument(help: "Path to the vault file.", completion: .file()) var path: String
  @Flag(name: .customLong("default"), help: "Also make it the default vault.") var makeDefault =
    false

  func run() async throws {
    var config = try CLIConfig.load()
    try config.checkAvailable(name)
    let absolute = CLIConfig.absolute(path)
    guard Vault.exists(databasePath: absolute) else {
      throw CLIError("\(absolute) is not a PassFort vault")
    }
    config.vaults[name] = absolute
    if makeDefault || config.defaultVault == nil { config.defaultVault = name }
    try config.save()
    let tail = config.defaultVault == name ? " (the default vault)" : ""
    print("added \"\(name)\" -> \(absolute)\(tail)")
  }
}

struct VaultUse: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "use", abstract: "Make a remembered vault the default.")

  @Argument(
    help: "A name from `vault list`.", completion: .custom(CLIConfig.completionNames))
  var name: String

  func run() async throws {
    var config = try CLIConfig.load()
    guard config.vaults[name] != nil else {
      throw CLIError("no vault named \"\(name)\" -- see `passfort-cli vault list`")
    }
    config.defaultVault = name
    try config.save()
    print("default vault: \(name)")
  }
}

struct VaultForget: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "forget", abstract: "Stop remembering a vault. The file itself is untouched.")

  @Argument(
    help: "A name from `vault list`.", completion: .custom(CLIConfig.completionNames))
  var name: String

  func run() async throws {
    var config = try CLIConfig.load()
    guard let path = config.vaults.removeValue(forKey: name) else {
      throw CLIError("no vault named \"\(name)\" -- see `passfort-cli vault list`")
    }
    var note = ""
    if config.defaultVault == name {
      config.defaultVault = nil
      note = "; there is no default vault now -- `vault use <name>` picks one"
    }
    try config.save()
    print("forgot \"\(name)\" (\(path) is untouched)\(note)")
  }
}
