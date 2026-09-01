import Foundation

/// Crockford's Base32 (ADR-0007): the alphabet is `0-9A-Z` minus `I L O U`, so
/// nothing is ambiguous when handwritten or read aloud. Decoding is tolerant --
/// any case, `I`/`L` → `1`, `O` → `0`, hyphens and spaces ignored -- and there is
/// an optional trailing check symbol (value mod 37) that catches a transcription
/// slip. Used only for the recovery key's display form; no crypto lives here.
enum CrockfordBase32 {
  private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
  /// The check alphabet extends the base with five symbols for values 32...36.
  private static let checkAlphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ*~$=U")

  enum Failure: Error, Equatable {
    case emptyInput
    case unknownSymbol(Character)
    case checksumMismatch
    case missingCheckSymbol
  }

  /// Encode `data` to Base32 symbols, most-significant bit first. No grouping, no
  /// check symbol -- callers add those.
  static func encode(_ data: Data) -> String {
    var out = ""
    var accumulator: UInt = 0
    var bits = 0
    for byte in data {
      accumulator = (accumulator << 8) | UInt(byte)
      bits += 8
      while bits >= 5 {
        bits -= 5
        out.append(alphabet[Int((accumulator >> UInt(bits)) & 0x1F)])
      }
    }
    if bits > 0 {
      out.append(alphabet[Int((accumulator << UInt(5 - bits)) & 0x1F)])
    }
    return out
  }

  /// Decode Base32 symbols back to bytes. `outputByteCount` is required because
  /// the last symbol may carry padding bits that are not a whole byte.
  static func decode(_ string: String, outputByteCount: Int) throws -> Data {
    var out = Data()
    out.reserveCapacity(outputByteCount)
    var accumulator: UInt = 0
    var bits = 0
    var sawSymbol = false
    for character in string {
      if character == "-" || character == " " { continue }
      let value = try symbolValue(character)
      sawSymbol = true
      accumulator = (accumulator << 5) | UInt(value)
      bits += 5
      if bits >= 8 {
        bits -= 8
        out.append(UInt8((accumulator >> UInt(bits)) & 0xFF))
      }
    }
    guard sawSymbol else { throw Failure.emptyInput }
    return Data(out.prefix(outputByteCount))
  }

  /// The Crockford check symbol for `data`: the 256-bit (or any-width) value mod
  /// 37, mapped through the check alphabet.
  static func checkSymbol(for data: Data) -> Character {
    var remainder = 0
    for byte in data {
      remainder = (remainder * 256 + Int(byte)) % 37
    }
    return checkAlphabet[remainder]
  }

  private static func symbolValue(_ character: Character) throws -> Int {
    switch character {
    case "0", "O", "o": return 0
    case "1", "I", "i", "L", "l": return 1
    default:
      guard let upper = character.uppercased().first,
        let index = alphabet.firstIndex(of: upper)
      else { throw Failure.unknownSymbol(character) }
      return index
    }
  }

  private static func checkSymbolValue(_ character: Character) throws -> Int {
    if let value = try? symbolValue(character) { return value }
    guard let upper = character.uppercased().first,
      let index = checkAlphabet.firstIndex(of: upper), index >= 32
    else { throw Failure.unknownSymbol(character) }
    return index
  }

  /// Verify that the final non-separator symbol of `string` is the check symbol
  /// for the bytes the rest of it decodes to. Returns the data on success.
  static func decodeChecked(_ string: String, outputByteCount: Int) throws -> Data {
    let symbols = string.filter { $0 != "-" && $0 != " " }
    guard let checkChar = symbols.last else { throw Failure.emptyInput }
    guard symbols.count > 1 else { throw Failure.missingCheckSymbol }

    let data = try decode(String(symbols.dropLast()), outputByteCount: outputByteCount)
    let expected = try checkSymbolValue(checkChar)
    let actual = try checkSymbolValue(checkSymbol(for: data))
    guard expected == actual else { throw Failure.checksumMismatch }
    return data
  }
}
