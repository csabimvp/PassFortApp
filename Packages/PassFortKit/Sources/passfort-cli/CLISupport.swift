import ArgumentParser
import Foundation

#if canImport(Glibc)
  import Glibc
#endif

struct CLIError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
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
}

// MARK: - UUID

/// Parse a record UUID from a CLI string (a retroactive `ExpressibleByArgument`
/// conformance on `UUID` would trip the formatter's lint).
func parseRecordID(_ string: String) throws -> UUID {
  guard let uuid = UUID(uuidString: string) else {
    throw CLIError("not a valid UUID: \(string)")
  }
  return uuid
}
