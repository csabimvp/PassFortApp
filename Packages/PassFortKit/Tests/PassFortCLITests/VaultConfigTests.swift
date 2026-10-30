import Foundation
import Testing

@testable import passfort_cli

/// Which vault a command acts on (`--vault`, `PASSFORT_VAULT`, the default) and how `init` and
/// `sync join` remember the vaults they create. No vault is opened.
@Suite struct VaultConfigTests {

  private let config = CLIConfig(
    vaults: ["personal": "/vaults/personal.sqlite", "work": "/vaults/work.sqlite"],
    defaultVault: "personal")

  // MARK: Resolving

  @Test func theFlagWinsOverTheVariableAndTheDefault() throws {
    let path = try config.resolve("work", environment: ["PASSFORT_VAULT": "personal"])
    #expect(path == "/vaults/work.sqlite")
  }

  @Test func theVariableWinsOverTheDefault() throws {
    #expect(
      try config.resolve(nil, environment: ["PASSFORT_VAULT": "work"]) == "/vaults/work.sqlite")
  }

  @Test func theDefaultIsTheLastResort() throws {
    #expect(try config.resolve(nil, environment: [:]) == "/vaults/personal.sqlite")
    #expect(
      try config.resolve("", environment: ["PASSFORT_VAULT": ""]) == "/vaults/personal.sqlite")
  }

  @Test func nothingToGoOnIsAnError() {
    #expect(throws: CLIError.self) { try CLIConfig().resolve(nil, environment: [:]) }
  }

  @Test func anUnknownNameIsAPathMadeAbsolute() throws {
    #expect(try config.resolve("/elsewhere/v.sqlite", environment: [:]) == "/elsewhere/v.sqlite")
    let relative = try config.resolve("v.sqlite", environment: [:])
    #expect(relative.hasPrefix("/") && relative.hasSuffix("/v.sqlite"))
    let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    #expect(CLIConfig.absolute("~/v.sqlite").hasPrefix(home.hasSuffix("/") ? home : home + "/"))
  }

  // MARK: Names

  @Test(arguments: ["personal", "work-2", "a.b_c", "Ő"])
  func goodNames(_ name: String) throws {
    try CLIConfig.validate(name: name)
  }

  @Test(arguments: ["", "-v", "a/b", "my vault", "../x"])
  func badNames(_ name: String) {
    #expect(throws: CLIError.self) { try CLIConfig.validate(name: name) }
  }

  @Test func aTakenNameIsRefusedBeforeAnythingIsCreated() {
    #expect(throws: CLIError.self) { try config.checkAvailable("work") }
  }

  // MARK: Registering

  @Test func theFirstVaultIsRememberedByItsFileNameAsTheDefault() {
    var empty = CLIConfig()
    let message = empty.registerNew(at: "/vaults/vault.sqlite", as: nil)
    #expect(empty == CLIConfig(vaults: ["vault": "/vaults/vault.sqlite"], defaultVault: "vault"))
    #expect(message.contains("default"))
  }

  @Test func laterVaultsNeedANameAndNeverTakeOverTheDefault() {
    var copy = config
    _ = copy.registerNew(at: "/vaults/other.sqlite", as: nil)
    #expect(copy == config, "no name and a default already: only a hint")

    _ = copy.registerNew(at: "/vaults/other.sqlite", as: "other")
    #expect(copy.vaults["other"] == "/vaults/other.sqlite")
    #expect(copy.defaultVault == "personal")
  }

  @Test func aFileNameThatIsTakenOrInvalidIsOnlyAHint() {
    var taken = CLIConfig(vaults: ["vault": "/a/vault.sqlite"])
    _ = taken.registerNew(at: "/b/vault.sqlite", as: nil)
    #expect(taken.vaults == ["vault": "/a/vault.sqlite"])

    var spaced = CLIConfig()
    _ = spaced.registerNew(at: "/b/my vault.sqlite", as: nil)
    #expect(spaced == CLIConfig())
  }

  // MARK: The file

  @Test func roundTripsThroughTheFileWithTightPermissions() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "pf-config-\(UUID().uuidString)/nested")
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    let url = directory.appending(path: "config.json")

    #expect(try CLIConfig.load(from: url) == CLIConfig(), "no file yet is an empty config")
    try config.save(to: url)
    #expect(try CLIConfig.load(from: url) == config)

    let attributes = try FileManager.default.attributesOfItem(
      atPath: url.path(percentEncoded: false))
    #expect((attributes[.posixPermissions] as? Int) == 0o600)
  }

  @Test func missingKeysDecodeAsEmpty() throws {
    let decoded = try JSONDecoder().decode(CLIConfig.self, from: Data("{}".utf8))
    #expect(decoded == CLIConfig())
  }
}
