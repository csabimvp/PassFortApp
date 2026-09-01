import ArgumentParser
import Foundation
import PassFortCrypto

@main
struct PassFortCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "passfort-cli",
    abstract: "PassFort vault tool. M1 exercises the crypto core; storage arrives in M2.",
    subcommands: [Bench.self, Init.self, Unlock.self, Seal.self, Open.self, Seam.self]
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

// MARK: - init

struct Init: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Create a new vault file (M1: the §5.3 header blob).")

  @Argument(help: "Path to the vault file to create.") var vault: String
  @Option(help: "Argon2id calibration target in milliseconds.") var targetMs: UInt32 = 500
  @Flag(help: "Overwrite the vault file if it already exists.") var force = false

  func run() throws {
    let password = try Password.promptConfirmed()
    let params = try VaultSession.calibrate(targetMs: targetMs)
    let header = try VaultSession.create(password: password, params: params)
    try Files.writeNew(header, to: vault, force: force)
    print("created \(vault) (\(header.count) bytes, \(params.memoryKiB / 1024) MiB Argon2id)")
  }
}

// MARK: - unlock

struct Unlock: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Open a session against a vault file and report the result.")

  @Argument(help: "Path to the vault file.") var vault: String

  func run() throws {
    let header = try Files.read(vault)
    let password = try Password.prompt("Vault password: ")
    do {
      _ = try VaultSession.open(header: header, password: password)
      print("unlocked OK")
    } catch PassFortError.authFailed {
      throw CLIError("AuthFailed -- wrong password or corrupt vault")
    }
  }
}

// MARK: - seal

struct Seal: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Seal a file into a record blob.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Option(help: "Record UUID. A fresh one is generated if omitted.") var id: String?
  @Option(help: "Record version (AAD-bound).") var version: UInt64 = 1
  @Option(help: "Schema version (AAD-bound).") var schema: UInt16 = 1
  @Option(name: [.short, .long], help: "Plaintext input file. Reads stdin if omitted.")
  var input: String?
  @Option(name: [.short, .long], help: "Sealed output file. Writes stdout if omitted.")
  var output: String?

  func run() async throws {
    let session = try unlock(vault)
    let recordID = try id.map(parseRecordID) ?? UUID()
    let plaintext =
      try input.map { try Files.read($0) } ?? FileHandle.standardInput.readDataToEndOfFile()

    let sealed = try await session.seal(
      recordID: recordID, version: version, schema: schema, plaintext: plaintext)
    FileHandle.standardError.write(Data("id: \(recordID.uuidString)\n".utf8))
    try Files.emit(sealed, to: output)
  }
}

// MARK: - open

struct Open: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Open a sealed record blob back to plaintext.")

  @Argument(help: "Path to the vault file.") var vault: String
  @Option(help: "Record UUID the blob was sealed with.") var id: String
  @Option(help: "Record version the blob was sealed with.") var version: UInt64 = 1
  @Option(help: "Schema version the blob was sealed with.") var schema: UInt16 = 1
  @Option(name: [.short, .long], help: "Sealed input file. Reads stdin if omitted.")
  var input: String?
  @Option(name: [.short, .long], help: "Plaintext output file. Writes stdout if omitted.")
  var output: String?

  func run() async throws {
    let recordID = try parseRecordID(id)
    let session = try unlock(vault)
    let sealed =
      try input.map { try Files.read($0) } ?? FileHandle.standardInput.readDataToEndOfFile()
    do {
      let plaintext = try await session.open(
        recordID: recordID, version: version, schema: schema, sealed: sealed)
      try Files.emit(plaintext, to: output)
    } catch PassFortError.authFailed {
      throw CLIError("AuthFailed -- wrong id/version/schema, or the blob was tampered")
    }
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

// MARK: - shared

/// Read a vault file, prompt for the password, open a session.
private func unlock(_ vault: String) throws -> VaultSession {
  let header = try Files.read(vault)
  let password = try Password.prompt("Vault password: ")
  do {
    return try VaultSession.open(header: header, password: password)
  } catch PassFortError.authFailed {
    throw CLIError("AuthFailed -- wrong password or corrupt vault")
  }
}
