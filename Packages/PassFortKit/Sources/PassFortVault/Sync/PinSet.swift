import Foundation

/// SPKI pins: SHA-256 of a certificate's DER `SubjectPublicKeyInfo` (A.4, §9.4) -- the format
/// `openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256` prints. Pin the
/// CA keys of the served chain (intermediate + root), not the leaf: Azure renews the leaf on its
/// own schedule. Pins come from configuration (an `Info.plist` key for the app, a file for the
/// CLI), never from code.
public struct PinSet: Sendable, Equatable {
  public let hashes: Set<Data>

  public init(hashes: Set<Data>) {
    self.hashes = hashes
  }

  public enum InvalidPin: Error, Equatable {
    /// Not standard base64 of exactly 32 bytes.
    case notASHA256(String)
  }

  /// Pins as base64 strings, one per key.
  public init(base64 pins: [String]) throws {
    var hashes: Set<Data> = []
    for pin in pins {
      let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let hash = Data(base64Encoded: trimmed), hash.count == 32 else {
        throw InvalidPin.notASHA256(pin)
      }
      hashes.insert(hash)
    }
    self.init(hashes: hashes)
  }

  public static let none = PinSet(hashes: [])

  public var isEmpty: Bool { hashes.isEmpty }
}

// MARK: - Loopback and the SPKI hash

extension PinSet {
  /// The hosts that skip pinning and may use plain `http`: this machine only.
  static func isLoopback(host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
  }

  /// SHA-256 of the certificate's DER `SubjectPublicKeyInfo`, or `nil` if the DER doesn't parse.
  static func spkiHash(of certificateDER: Data) -> Data? {
    subjectPublicKeyInfo(in: certificateDER).map(PlatformCrypto.sha256)
  }

  /// The `SubjectPublicKeyInfo` TLV, whole, from an X.509 certificate (RFC 5280 4.1):
  /// `Certificate ::= SEQUENCE { tbsCertificate SEQUENCE { [0] version OPTIONAL, serialNumber,
  /// signature, issuer, validity, subject, subjectPublicKeyInfo, ... }, ... }`. Only lengths
  /// are read; nothing is interpreted, so any key type works.
  static func subjectPublicKeyInfo(in certificateDER: Data) -> Data? {
    var outer = DERReader(Array(certificateDER))
    guard let certificate = outer.next(), certificate.tag == 0x30 else { return nil }
    var inCertificate = DERReader(certificate.content)
    guard let tbs = inCertificate.next(), tbs.tag == 0x30 else { return nil }
    var fields = DERReader(tbs.content)
    guard var field = fields.next() else { return nil }
    if field.tag == 0xA0 {  // explicit [0] version
      guard let next = fields.next() else { return nil }
      field = next
    }
    // field is serialNumber; skip it and signature, issuer, validity, subject.
    for _ in 0..<4 { guard fields.next() != nil else { return nil } }
    guard let spki = fields.next(), spki.tag == 0x30 else { return nil }
    return Data(spki.whole)
  }
}

/// Just enough DER to walk a certificate: tag, definite length (short or long form), content.
private struct DERReader {
  struct Element {
    let tag: UInt8
    let content: [UInt8]
    let whole: [UInt8]
  }

  private let bytes: [UInt8]
  private var offset = 0

  init(_ bytes: [UInt8]) {
    self.bytes = bytes
  }

  mutating func next() -> Element? {
    let start = offset
    guard offset + 2 <= bytes.count else { return nil }
    let tag = bytes[offset]
    var length = Int(bytes[offset + 1])
    offset += 2
    if length & 0x80 != 0 {
      let count = length & 0x7F
      guard (1...4).contains(count), offset + count <= bytes.count else { return nil }
      length = bytes[offset..<offset + count].reduce(0) { ($0 << 8) | Int($1) }
      offset += count
    }
    guard length >= 0, offset + length <= bytes.count else { return nil }
    let content = Array(bytes[offset..<offset + length])
    offset += length
    return Element(tag: tag, content: content, whole: Array(bytes[start..<offset]))
  }
}
