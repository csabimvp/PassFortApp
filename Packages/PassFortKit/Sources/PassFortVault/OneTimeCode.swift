import Foundation

/// RFC 6238 time-based one-time codes, and the `otpauth://` URI that carries a `TOTPConfig` in
/// and out of other apps.
///
/// Pure Swift over the platform's HMAC (`PlatformCrypto`: CryptoKit, or libcrypto on Linux). The
/// shared seed is **record payload, not key material**: it sits decrypted in `AccountPayload` the
/// same way a password does (§3.4), so computing the code in C++ would buy nothing -- the same
/// reasoning as `PasswordPolicy`. The vault keys stay in C++; this never sees one. Known-answer tested against RFC 6238 Appendix B.

// MARK: - Codes

extension TOTPConfig {
  /// The code valid at `date`, zero-padded to `digits`.
  public func code(at date: Date = Date()) -> String {
    let counter = UInt64(max(0, date.timeIntervalSince1970) / Double(max(period, 1)))
    var message = counter.bigEndian
    let counterBytes = withUnsafeBytes(of: &message) { Data($0) }

    let mac = PlatformCrypto.hmac(algorithm, key: secret, message: counterBytes)

    // RFC 4226 §5.3 dynamic truncation.
    let offset = Int(mac[mac.count - 1] & 0x0F)
    let binary =
      (UInt32(mac[offset] & 0x7F) << 24) | (UInt32(mac[offset + 1]) << 16)
      | (UInt32(mac[offset + 2]) << 8) | UInt32(mac[offset + 3])
    var modulus: UInt64 = 1
    for _ in 0..<digits { modulus *= 10 }
    let value = UInt64(binary) % modulus
    let text = String(value)
    return String(repeating: "0", count: max(0, digits - text.count)) + text
  }

  /// Whole seconds until the code at `date` rolls over -- for a countdown.
  public func secondsRemaining(at date: Date = Date()) -> Int {
    let step = max(period, 1)
    let elapsed = Int(max(0, date.timeIntervalSince1970)) % step
    return step - elapsed
  }
}

// MARK: - otpauth:// and bare secrets

public enum OneTimeCodeError: Error, Equatable {
  /// Neither an `otpauth://totp/...` URI nor a Base32 secret.
  case unrecognized
  /// An `otpauth://hotp/...` URI -- counter-based codes are not supported.
  case counterBasedNotSupported
  /// The URI has no `secret` parameter.
  case missingSecret
  /// The secret is not valid RFC 4648 Base32, or decodes to nothing.
  case badSecret
  case unsupportedAlgorithm(String)
  /// `digits` outside 6...10.
  case badDigits
  /// `period` not a positive number of seconds.
  case badPeriod
}

extension TOTPConfig {
  /// Parse what a user pastes or an importer reads: an `otpauth://totp/...` URI, or a bare Base32
  /// secret (spaces, hyphens and case ignored), which gets the RFC defaults (SHA-1, 6 digits, 30 s).
  public init(parsing input: String) throws {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.lowercased().hasPrefix("otpauth://") {
      try self.init(otpauth: trimmed)
    } else if let secret = Base32.decode(trimmed), !secret.isEmpty {
      self.init(secret: secret)
    } else {
      throw OneTimeCodeError.unrecognized
    }
  }

  /// Parse the Key URI Format (`otpauth://totp/Issuer:account?secret=...&issuer=...`).
  public init(otpauth uri: String) throws {
    guard let components = URLComponents(string: uri),
      components.scheme?.lowercased() == "otpauth"
    else { throw OneTimeCodeError.unrecognized }
    switch components.host?.lowercased() {
    case "totp": break
    case "hotp": throw OneTimeCodeError.counterBasedNotSupported
    default: throw OneTimeCodeError.unrecognized
    }

    var query: [String: String] = [:]
    for item in components.queryItems ?? [] {
      if let value = item.value { query[item.name.lowercased()] = value }
    }

    guard let rawSecret = query["secret"] else { throw OneTimeCodeError.missingSecret }
    guard let secret = Base32.decode(rawSecret), !secret.isEmpty else {
      throw OneTimeCodeError.badSecret
    }

    let algorithm: TOTPAlgorithm
    switch query["algorithm"]?.uppercased() ?? "SHA1" {
    case "SHA1": algorithm = .sha1
    case "SHA256": algorithm = .sha256
    case "SHA512": algorithm = .sha512
    case let other: throw OneTimeCodeError.unsupportedAlgorithm(other)
    }

    let digits =
      try query["digits"].map { text in
        guard let value = Int(text), (6...10).contains(value) else {
          throw OneTimeCodeError.badDigits
        }
        return value
      } ?? 6
    let period =
      try query["period"].map { text in
        guard let value = Int(text), value > 0 else { throw OneTimeCodeError.badPeriod }
        return value
      } ?? 30

    // The path is "/Issuer:account" or "/account"; an explicit issuer parameter wins.
    let path = String(components.path.drop(while: { $0 == "/" }))
    var label: String? = path.isEmpty ? nil : path
    var issuer = query["issuer"]
    if let colon = path.firstIndex(of: ":") {
      let prefix = String(path[..<colon])
      label = String(path[path.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
      if issuer == nil { issuer = prefix }
    }

    self.init(
      secret: secret, algorithm: algorithm, digits: digits, period: period, issuer: issuer,
      label: label)
  }

  /// The Key URI Format form -- what an export writes and what the edit form shows.
  public var otpauthURI: String {
    var components = URLComponents()
    components.scheme = "otpauth"
    components.host = "totp"
    let name = [issuer, label].compactMap { $0 }.joined(separator: ":")
    components.path = "/" + name
    var items = [URLQueryItem(name: "secret", value: Base32.encode(secret))]
    if let issuer { items.append(URLQueryItem(name: "issuer", value: issuer)) }
    if algorithm != .sha1 {
      items.append(URLQueryItem(name: "algorithm", value: algorithm.rawValue.uppercased()))
    }
    if digits != 6 { items.append(URLQueryItem(name: "digits", value: String(digits))) }
    if period != 30 { items.append(URLQueryItem(name: "period", value: String(period))) }
    components.queryItems = items
    return components.string ?? "otpauth://totp/?secret=\(Base32.encode(secret))"
  }
}

// MARK: - RFC 4648 Base32

/// RFC 4648 Base32 -- the alphabet authenticator secrets use. Not `CrockfordBase32`, which is the
/// recovery key's alphabet (different symbols, a check digit).
enum Base32 {
  private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

  /// Lenient decode: case-insensitive, ignores spaces, hyphens and `=` padding. `nil` on any other
  /// character or a length no encoder produces.
  static func decode(_ text: String) -> Data? {
    var bits: UInt32 = 0
    var bitCount = 0
    var out = Data()
    var symbols = 0
    for character in text.uppercased() {
      if character == " " || character == "-" || character == "=" { continue }
      guard let index = alphabet.firstIndex(of: character) else { return nil }
      bits = (bits << 5) | UInt32(index)
      bitCount += 5
      symbols += 1
      if bitCount >= 8 {
        bitCount -= 8
        out.append(UInt8((bits >> UInt32(bitCount)) & 0xFF))
      }
    }
    // 1, 3 and 6 trailing symbols can't come from whole bytes.
    guard ![1, 3, 6].contains(symbols % 8) else { return nil }
    return out
  }

  /// Unpadded, upper-case -- what authenticator apps expect in a URI.
  static func encode(_ data: Data) -> String {
    var bits: UInt32 = 0
    var bitCount = 0
    var out = ""
    for byte in data {
      bits = (bits << 8) | UInt32(byte)
      bitCount += 8
      while bitCount >= 5 {
        bitCount -= 5
        out.append(alphabet[Int((bits >> UInt32(bitCount)) & 0x1F)])
      }
    }
    if bitCount > 0 { out.append(alphabet[Int((bits << UInt32(5 - bitCount)) & 0x1F)]) }
    return out
  }
}
