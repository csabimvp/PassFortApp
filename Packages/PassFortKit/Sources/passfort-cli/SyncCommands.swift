import ArgumentParser
import Foundation
import PassFortCrypto
import PassFortVault

// `passfort-cli sync` (`m5-sync.md` Phase 11): the CLI front end onto `SyncEngine`. Two CLI
// "devices" converge through the API here before the app is wired to the same engine.

struct Sync: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Sync the vault through a PassFort sync server (M5).",
    discussion: """
      The server stores only sealed records and the header -- never a key or a password. \
      `http://` is accepted for localhost only; an `https://` endpoint needs SPKI pins (--pins, or \
      ~/.config/passfort/pins: one base64 SHA-256 per line). Set \(CLIDevice.fileVariable) to act \
      as another device on this machine.
      """,
    subcommands: [
      SyncEnable.self, SyncJoin.self, SyncNow.self, SyncStatus.self, SyncDevices.self,
      SyncDisable.self,
    ])
}

/// `--pins`, shared by the commands that reach the server.
struct PinOptions: ParsableArguments {
  @Option(help: "SPKI pin file for an https endpoint (default: ~/.config/passfort/pins).")
  var pins: String?
}

// MARK: - enable

struct SyncEnable: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "enable",
    abstract: "Put this vault on a sync server and upload every record. Prints the vault id.")

  @OptionGroup var vaultOption: VaultOption
  @Option(help: "The API root, e.g. https://<site>.azurestaticapps.net/api/v1.") var endpoint:
    String
  @Option(help: "The server's enrollment secret (prompted for if omitted -- keeps it out of `ps`).")
  var enrollSecret: String?
  @OptionGroup var pinOptions: PinOptions

  func run() async throws {
    let vault = try vaultOption.path()
    let endpoint = try parseURL(self.endpoint)
    let api = try SyncCLI.api(endpoint, pins: pinOptions.pins)  // refused before any prompt
    let repo = try await VaultCLI.open(vault)
    if let state = try await repo.syncState() {
      throw CLIError(
        "\(vault) already syncs to \(state.endpoint) as \(SyncCLI.id(state.vaultID)) -- `sync disable` first"
      )
    }
    let secret =
      try enrollSecret ?? String(decoding: Password.prompt("Enrollment secret: "), as: UTF8.self)

    let engine = try SyncCLI.engine(repo, api)
    let vaultID = try await SyncCLI.mapping {
      try await engine.enable(endpoint: endpoint, enrollSecret: secret)
    }
    print("sync enabled -- vault id \(SyncCLI.id(vaultID))")
    try await SyncCLI.runAndReport(engine)
    print(
      """
      join another device with:
          passfort-cli sync join <new vault file> --endpoint \(endpoint) --vault-id \(SyncCLI.id(vaultID))
      """)
  }
}

// MARK: - join

struct SyncJoin: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "join",
    abstract: "Create a vault file from a synced vault and download every record.")

  @Argument(help: "Path for the new vault file (must not exist).", completion: .file())
  var vault: String
  @Option(help: "The API root the vault syncs through.") var endpoint: String
  @Option(help: "Remember the new vault under this name (as `init --name`).") var name: String?
  @Option(help: "The vault id `sync enable` printed.") var vaultId: String
  @OptionGroup var pinOptions: PinOptions

  func run() async throws {
    let endpoint = try parseURL(self.endpoint)
    guard let vaultID = UUID(uuidString: vaultId) else {
      throw CLIError("not a vault id: \(vaultId)")
    }
    let api = try SyncCLI.api(endpoint, pins: pinOptions.pins)
    var config = try CLIConfig.load()
    if let name { try config.checkAvailable(name) }
    guard !FileManager.default.fileExists(atPath: vault) else {
      throw CLIError("\(vault) already exists -- join into a new file")
    }

    let password = try Password.prompt("Vault password (the synced vault's): ")
    let repo: VaultRepository
    do {
      repo = try await SyncCLI.mapping {
        try await Vault.join(
          databasePath: vault, password: password, api: api, endpoint: endpoint, vaultID: vaultID,
          deviceID: try CLIDevice.id())
      }
    } catch PassFortError.authFailed {
      throw CLIError("AuthFailed -- wrong password, or the server's header is not genuine")
    }
    print("joined \(SyncCLI.id(vaultID)) into \(vault)")
    let before = config
    let registered = config.registerNew(at: vault, as: name)
    if config != before { try config.save() }
    print(registered)
    try await SyncCLI.runAndReport(try SyncCLI.engine(repo, api))
  }
}

// MARK: - now

struct SyncNow: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "now", abstract: "Pull, reconcile and push once.")

  @OptionGroup var vaultOption: VaultOption
  @OptionGroup var pinOptions: PinOptions

  func run() async throws {
    let vault = try vaultOption.path()
    let (repo, state) = try await SyncCLI.openSynced(vault)
    let api = try SyncCLI.api(state.endpoint, pins: pinOptions.pins)
    try await SyncCLI.runAndReport(try SyncCLI.engine(repo, api))
  }
}

// MARK: - status

struct SyncStatus: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status", abstract: "Where this vault syncs and how far it has got. No network.")

  @OptionGroup var vaultOption: VaultOption

  func run() async throws {
    let vault = try vaultOption.path()
    let (_, state) = try await SyncCLI.openSynced(vault)
    let device = try CLIDevice.identity()
    var header = state.headerVersion.map { "version \($0)" } ?? "never pushed"
    if state.headerDirty { header += " (changed here, not pushed yet)" }
    if let pending = state.pendingHeaderVersion {
      header += "; version \(pending) from another device waits for the next unlock"
    }
    let iso = ISO8601DateFormatter()
    print(
      """
      endpoint   \(state.endpoint)
      vault id   \(SyncCLI.id(state.vaultID))
      device     \(device.name) (\(SyncCLI.id(device.id)))
      enabled    \(iso.string(from: state.enabledAt))
      cursor     \(state.cursor)\(state.cursor == 0 ? " (the next run is a full resync)" : "")
      to push    \(state.dirtyCount) record\(state.dirtyCount == 1 ? "" : "s")
      header     \(header)
      last sync  \(state.lastSyncedAt.map { iso.string(from: $0) } ?? "never")
      """)
  }
}

// MARK: - devices

struct SyncDevices: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "devices", abstract: "List the devices syncing this vault, or remove one.")

  @OptionGroup var vaultOption: VaultOption
  @Option(help: "Remove this device id. If it syncs again it resyncs from scratch.")
  var remove: String?
  @OptionGroup var pinOptions: PinOptions

  func run() async throws {
    let vault = try vaultOption.path()
    let (repo, state) = try await SyncCLI.openSynced(vault)
    let engine = try SyncCLI.engine(repo, try SyncCLI.api(state.endpoint, pins: pinOptions.pins))
    if let remove {
      guard let id = UUID(uuidString: remove) else { throw CLIError("not a device id: \(remove)") }
      try await SyncCLI.mapping { try await engine.removeDevice(id) }
      print("removed \(SyncCLI.id(id))")
      return
    }

    let me = try CLIDevice.id()
    let iso = ISO8601DateFormatter()
    let devices = try await SyncCLI.mapping { try await engine.devices() }
    print("ID                                    PLATFORM  LAST SEQ  LAST SEEN             NAME")
    for device in devices.sorted(by: { $0.lastSeenAt > $1.lastSeenAt }) {
      let marker = device.id == me ? "  (this device)" : ""
      print(
        "\(SyncCLI.id(device.id))  \(device.platform.rawValue.padding(8))  "
          + "\(String(device.lastSeq).padding(8))  \(iso.string(from: device.lastSeenAt))  "
          + "\(device.name)\(marker)")
    }
  }
}

// MARK: - disable

struct SyncDisable: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "disable",
    abstract: "Stop syncing this vault. Its records stay; the server copy stays unless deleted.")

  @OptionGroup var vaultOption: VaultOption
  @Flag(help: "Also delete the server copy -- every device's synced data on the server.")
  var deleteServerCopy = false
  @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false
  @OptionGroup var pinOptions: PinOptions

  func run() async throws {
    let vault = try vaultOption.path()
    let (repo, state) = try await SyncCLI.openSynced(vault)
    if deleteServerCopy {
      if !yes {
        FileHandle.standardError.write(
          Data(
            """
            Delete the server copy of \(SyncCLI.id(state.vaultID)) at \(state.endpoint)?
            Other devices keep their files but can no longer sync. Type "yes" to continue:
            """.utf8))
        guard readLine(strippingNewline: true) == "yes" else {
          throw CLIError("not confirmed -- nothing changed")
        }
      }
      let engine = try SyncCLI.engine(repo, try SyncCLI.api(state.endpoint, pins: pinOptions.pins))
      try await SyncCLI.mapping { try await engine.deleteServerCopy() }
      print("server copy deleted")
    }
    try await repo.disableSync()
    print("sync disabled for \(vault) -- its records are unchanged")
  }
}

// MARK: - Support

enum SyncCLI {
  /// The CLI's pins: `--pins`, else `~/.config/passfort/pins` if it exists, else none (enough
  /// for a loopback endpoint only). One base64 SHA-256 per line; blank lines and `#` comments
  /// are skipped.
  static func pinSet(_ path: String?) throws -> PinSet {
    let file =
      path
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appending(path: ".config/passfort/pins").path(percentEncoded: false)
    guard path != nil || FileManager.default.fileExists(atPath: file) else { return .none }
    let lines = String(decoding: try Files.read(file), as: UTF8.self)
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    do {
      return try PinSet(base64: lines)
    } catch {
      throw CLIError("\(file): not a list of base64 SHA-256 pins (\(error))")
    }
  }

  /// The client for `endpoint` -- refused here, before any password prompt, if it would send
  /// `k_auth` in the clear or unpinned (Phase 7.2).
  static func api(_ endpoint: URL, pins path: String?) throws -> HTTPSyncAPI {
    let pins = try pinSet(path)
    do {
      return try HTTPSyncAPI(endpoint: endpoint, pins: pins)
    } catch SyncError.insecureEndpoint {
      throw CLIError("refusing \(endpoint): use https (plain http is allowed for localhost only)")
    } catch SyncError.noPins {
      throw CLIError(
        "no SPKI pins for \(endpoint) -- pass --pins <file> or create ~/.config/passfort/pins")
    }
  }

  static func engine(_ repo: VaultRepository, _ api: any SyncAPI) throws -> SyncEngine {
    SyncEngine(
      api: api, repository: repo, device: DeviceDTO(try CLIDevice.identity(), platform: .cli))
  }

  /// Unlock `path` and require sync to be on.
  static func openSynced(_ path: String) async throws -> (
    VaultRepository, VaultRepository.SyncState
  ) {
    let repo = try await VaultCLI.open(path)
    guard let state = try await repo.syncState() else {
      throw CLIError("sync is off for \(path) -- `sync enable` or `sync join` first")
    }
    return (repo, state)
  }

  static func runAndReport(_ engine: SyncEngine) async throws {
    let report = try await mapping { try await engine.run() }
    var parts = ["pulled \(report.pulled)", "pushed \(report.pushed)"]
    if report.conflictCopies > 0 { parts.append("\(report.conflictCopies) conflict copies made") }
    if report.fullResync { parts.append("full resync, \(report.reuploaded) re-uploaded") }
    print("synced -- " + parts.joined(separator: ", "))
  }

  /// Run `body`, turning a `SyncError` into a message that says what to do.
  @discardableResult
  static func mapping<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let error as SyncError {
      throw CLIError(describe(error))
    }
  }

  static func describe(_ error: SyncError) -> String {
    switch error {
    case .insecureEndpoint: return "refusing a plain-http endpoint off localhost"
    case .noPins: return "no SPKI pins for an https endpoint"
    case .offline: return "offline -- the server can't be reached"
    case .pinningFailed:
      return
        "the server's certificate chain matches no pin -- sync stopped; update the pins, never bypass them"
    case .redirectRefused: return "the server answered with a redirect, which is refused"
    case .invalidResponse: return "the server's response doesn't match the contract"
    case .badRequest: return "the server refused the request as malformed (a client bug)"
    case .unauthorized:
      return "unauthorized -- the server doesn't accept this vault's key (was the vault recreated?)"
    case .forbidden: return "wrong enrollment secret"
    case .notFound: return "no such vault or device on the server"
    case .vaultExists: return "a vault with this id already exists on the server"
    case .conflicts: return "other devices kept pushing; run `sync now` again"
    case .headerConflict: return "another device changed the header first"
    case .resyncRequired: return "the server needs a full resync"
    case .tooLarge: return "a record or batch is over the server's size limit"
    case .rateLimited(let after): return "rate limited -- try again in \(Int(after.rounded(.up))) s"
    case .server(let status, _): return "server error \(status) -- try again later"
    case .notEnabled: return "sync is off for this vault"
    case .serverRollback:
      return """
        the server is behind what this vault already has -- it was rolled back or replaced. Sync \
        stopped; nothing was changed here.
        """
    case .tamperedRecord(let record):
      return """
        record \(id(record)) from the server fails to decrypt -- forged or altered. Nothing from that \
        page was applied. If it repeats, treat the server as compromised.
        """
    case .headerChangedElsewhere:
      return """
        records synced, but another device changed the master password or recovery key first: \
        this device's change was discarded. Unlock with the other device's password to take \
        its header.
        """
    }
  }

  static func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }
}

extension String {
  fileprivate func padding(_ width: Int) -> String {
    count >= width ? self : self + String(repeating: " ", count: width - count)
  }
}
