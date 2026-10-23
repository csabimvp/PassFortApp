import CryptoKit
import Foundation
import Security
import os

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

/// The `URLSession` delegate for sync traffic: server trust (normal evaluation, then the pins)
/// and redirects (refused). Loopback hosts skip pinning -- that is the local `npm run dev` loop.
///
/// It handles trust at the **task** level (no session-level challenge method), so a pinning
/// failure is recorded against the task that hit it and `HTTPSyncAPI` can report `.pinningFailed`
/// rather than a bare cancellation.
final class PinnedTransport: NSObject, URLSessionTaskDelegate, Sendable {
  private let pins: PinSet
  private let pinFailures = OSAllocatedUnfairLock(initialState: Set<Int>())

  init(pins: PinSet) {
    self.pins = pins
  }

  /// True once, if `taskIdentifier` was cancelled because its server failed trust or the pins.
  func takePinFailure(_ taskIdentifier: Int) -> Bool {
    pinFailures.withLock { $0.remove(taskIdentifier) != nil }
  }

  // MARK: URLSessionTaskDelegate

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) ->
      Void
  ) {
    let space = challenge.protectionSpace
    guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
      return completionHandler(.performDefaultHandling, nil)
    }
    if Self.isLoopback(host: space.host) { return completionHandler(.performDefaultHandling, nil) }
    guard let trust = space.serverTrust, Self.evaluate(trust, pins: pins) else {
      pinFailures.withLock { _ = $0.insert(task.taskIdentifier) }
      return completionHandler(.cancelAuthenticationChallenge, nil)
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
  }

  /// Never follow a redirect: the API doesn't issue them, and one could move the request -- and
  /// its token -- to another host or scheme. The `3xx` itself comes back as the response.
  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  // MARK: The decision

  /// The hosts that skip pinning and may use plain `http`: this machine only.
  static func isLoopback(host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
  }

  /// Trust the chain the system way first (`SecTrustEvaluateWithError`: anchors, validity, the
  /// hostname, revocation as configured), then require at least one certificate in it whose SPKI
  /// hash is pinned. An empty pin set trusts nothing.
  static func evaluate(_ trust: SecTrust, pins: PinSet) -> Bool {
    guard !pins.isEmpty, SecTrustEvaluateWithError(trust, nil),
      let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
    else { return false }
    return chain.contains { certificate in
      spkiHash(of: SecCertificateCopyData(certificate) as Data).map(pins.hashes.contains) ?? false
    }
  }

  /// SHA-256 of the certificate's DER `SubjectPublicKeyInfo`, or `nil` if the DER doesn't parse.
  static func spkiHash(of certificateDER: Data) -> Data? {
    subjectPublicKeyInfo(in: certificateDER).map { Data(SHA256.hash(data: $0)) }
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
