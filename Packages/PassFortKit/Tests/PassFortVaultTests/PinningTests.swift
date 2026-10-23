import Foundation
import Security
import Testing

@testable import PassFortVault

/// SPKI pinning (m5-sync.md 7.3) against `Fixtures/pinning`: a throwaway root -> intermediate ->
/// leaf chain for `sync.test`, whose expected pins were computed with OpenSSL (see its README),
/// not by the code under test.
@Suite struct PinningTests {

  static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appending(path: "Fixtures/pinning")

  private let rootPin = "wYv+2XJZODvpQGEdrdNF/YPobcweZUdlpXSz8PnQbcU="
  private let intermediatePin = "M1AWPj3AZEniRAxIO4lxAIEtRyVX2LOoj7MHpuzGpDU="
  private let leafPin = "PCClOeEVI70kyhMRHlM0Ey9Ab6qASnZCpuismnykSMg="
  private let unrelatedPin = "ZfrT1aasVhxA4K/WebS2zC/1ET4G9W9rBgbWcHqHchQ="

  private func der(_ name: String) throws -> Data {
    try Data(contentsOf: Self.dir.appending(path: "\(name).der"))
  }

  private func certificate(_ name: String) throws -> SecCertificate {
    try #require(SecCertificateCreateWithData(nil, try der(name) as CFData))
  }

  /// A trust for the leaf + intermediate as a server would send them, checked as `host`, at a
  /// fixed date inside the leaf's validity, with no network. `anchored`: trust only the test root
  /// (otherwise the system roots, which don't know it).
  private func trust(host: String = "sync.test", anchored: Bool = true) throws -> SecTrust {
    var trust: SecTrust?
    let status = SecTrustCreateWithCertificates(
      [try certificate("leaf"), try certificate("int")] as CFArray,
      SecPolicyCreateSSL(true, host as CFString), &trust)
    let made = try #require(status == errSecSuccess ? trust : nil)
    if anchored {
      SecTrustSetAnchorCertificates(made, [try certificate("root")] as CFArray)
      SecTrustSetAnchorCertificatesOnly(made, true)
    }
    SecTrustSetNetworkFetchAllowed(made, false)
    SecTrustSetVerifyDate(made, Date(timeIntervalSince1970: 1_800_000_000) as CFDate)  // 2027-01-15
    return made
  }

  // MARK: - The SPKI hash

  @Test func spkiHashesMatchOpenSSL() throws {
    let expected = [("root", rootPin), ("int", intermediatePin), ("leaf", leafPin)]
    for (name, pin) in expected {
      let hash = try #require(PinnedTransport.spkiHash(of: try der(name)))
      #expect(hash.base64EncodedString() == pin, "\(name)")
    }
  }

  @Test func garbageIsNotACertificate() {
    #expect(PinnedTransport.spkiHash(of: Data()) == nil)
    #expect(PinnedTransport.spkiHash(of: Data([0x30, 0x82, 0xFF, 0xFF])) == nil)
    #expect(PinnedTransport.spkiHash(of: Data(repeating: 0x30, count: 64)) == nil)
  }

  // MARK: - The decision

  @Test func aPinnedCertificateAnywhereInTheChainPasses() throws {
    for pin in [intermediatePin, rootPin, leafPin] {
      #expect(PinnedTransport.evaluate(try trust(), pins: try PinSet(base64: [pin])), "\(pin)")
    }
    let both = try PinSet(base64: [unrelatedPin, intermediatePin])
    #expect(PinnedTransport.evaluate(try trust(), pins: both))
  }

  @Test func aTrustedChainWithNoPinnedKeyFails() throws {
    #expect(!PinnedTransport.evaluate(try trust(), pins: try PinSet(base64: [unrelatedPin])))
    #expect(!PinnedTransport.evaluate(try trust(), pins: .none), "an empty pin set trusts nothing")
  }

  @Test func aPinnedKeyDoesNotRescueAnUntrustedChain() throws {
    let pins = try PinSet(base64: [intermediatePin, rootPin, leafPin])
    #expect(!PinnedTransport.evaluate(try trust(anchored: false), pins: pins), "unknown root")
    #expect(!PinnedTransport.evaluate(try trust(host: "other.test"), pins: pins), "wrong host")
  }

  // MARK: - Loopback and the pin set

  @Test func onlyThisMachineSkipsPinning() {
    for host in ["localhost", "LOCALHOST", "127.0.0.1", "::1", "[::1]"] {
      #expect(PinnedTransport.isLoopback(host: host), "\(host)")
    }
    for host in ["sync.test", "127.0.0.2", "10.0.0.1", "localhost.evil.test", "", nil] as [String?] {
      #expect(!PinnedTransport.isLoopback(host: host), "\(host ?? "nil")")
    }
  }

  @Test func pinsMustBeBase64SHA256s() throws {
    #expect(try PinSet(base64: [" \(leafPin)\n"]).hashes.count == 1)
    #expect(throws: PinSet.InvalidPin.self) { try PinSet(base64: ["not base64"]) }
    #expect(throws: PinSet.InvalidPin.self) { try PinSet(base64: [Data(count: 20).base64EncodedString()]) }
  }
}
