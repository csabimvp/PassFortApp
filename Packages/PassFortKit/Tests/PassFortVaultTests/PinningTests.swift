#if canImport(Security)
  import Foundation
  import Security
  import Testing

  @testable import PassFortVault

  /// SPKI pinning's decision on Apple platforms (m5-sync.md 7.3): `PinnedTransport.evaluate` over
  /// a `SecTrust` for `PinningFixtures`. `LinuxPinningTests` runs the same cases through OpenSSL.
  @Suite struct PinningTests {

    private func certificate(_ name: String) throws -> SecCertificate {
      try #require(SecCertificateCreateWithData(nil, try PinningFixtures.der(name) as CFData))
    }

    /// A trust for the leaf + intermediate as a server would send them, checked as `host`, at a
    /// fixed date inside the leaf's validity, with no network. `anchored`: trust only the test
    /// root (otherwise the system roots, which don't know it).
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
      SecTrustSetVerifyDate(made, PinningFixtures.verifyTime as CFDate)
      return made
    }

    private func pins(_ base64: String...) throws -> PinSet { try PinSet(base64: base64) }

    @Test func aPinnedCertificateAnywhereInTheChainPasses() throws {
      for pin in [
        PinningFixtures.intermediatePin, PinningFixtures.rootPin, PinningFixtures.leafPin,
      ] {
        #expect(PinnedTransport.evaluate(try trust(), pins: try pins(pin)), "\(pin)")
      }
      let both = try pins(PinningFixtures.unrelatedPin, PinningFixtures.intermediatePin)
      #expect(PinnedTransport.evaluate(try trust(), pins: both))
    }

    @Test func aTrustedChainWithNoPinnedKeyFails() throws {
      #expect(!PinnedTransport.evaluate(try trust(), pins: try pins(PinningFixtures.unrelatedPin)))
      #expect(
        !PinnedTransport.evaluate(try trust(), pins: .none), "an empty pin set trusts nothing")
    }

    @Test func aPinnedKeyDoesNotRescueAnUntrustedChain() throws {
      let all = try pins(
        PinningFixtures.intermediatePin, PinningFixtures.rootPin, PinningFixtures.leafPin)
      #expect(!PinnedTransport.evaluate(try trust(anchored: false), pins: all), "unknown root")
      #expect(!PinnedTransport.evaluate(try trust(host: "other.test"), pins: all), "wrong host")
    }
  }
#endif
