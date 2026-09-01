import Foundation

/// The recovery key (§5.6, ADR-0007): 256 bits from the system CSPRNG that wrap a
/// second copy of the DEK in header slot 1. Shown once at vault creation, never
/// stored. The display form is Crockford Base32 -- 52 symbols plus a check symbol,
/// in hyphen-separated groups of four.
public struct RecoveryKey: Sendable, Equatable {
  /// The 32 raw bytes -- fed straight to `VaultSession` (no Argon2).
  public let raw: Data

  public enum Failure: Error, Equatable {
    case wrongLength
    case malformed
  }

  public init(raw: Data) throws {
    guard raw.count == 32 else { throw Failure.wrongLength }
    self.raw = raw
  }

  private init(validated raw: Data) {
    self.raw = raw
  }

  /// A fresh key from the system CSPRNG (`SystemRandomNumberGenerator` is
  /// cryptographically secure on the platforms this ships to).
  public static func generate() -> RecoveryKey {
    var rng = SystemRandomNumberGenerator()
    var bytes = Data(count: 32)
    for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &rng) }
    return RecoveryKey(validated: bytes)
  }

  /// The write-this-down form: `XXXX-XXXX-…-XXXX-C`, where `C` is the check
  /// symbol. 52 data symbols (256 bits) in 13 groups of four, then the check.
  public var grouped: String {
    let symbols = Array(CrockfordBase32.encode(raw))
    let groups = stride(from: 0, to: symbols.count, by: 4).map { start in
      String(symbols[start..<min(start + 4, symbols.count)])
    }
    return groups.joined(separator: "-") + "-" + String(CrockfordBase32.checkSymbol(for: raw))
  }

  /// Parse the grouped form. Case-insensitive; hyphens/spaces optional; `I`/`L` →
  /// `1`, `O` → `0`; the trailing check symbol is verified.
  public init(grouped: String) throws {
    do {
      let raw = try CrockfordBase32.decodeChecked(grouped, outputByteCount: 32)
      try self.init(raw: raw)
    } catch let failure as Failure {
      throw failure
    } catch {
      throw Failure.malformed
    }
  }
}
