#if os(Linux)
  import CLinuxTLS
  import Foundation
  import Testing

  @testable import PassFortVault

  /// SPKI pinning's decision on Linux (ADR-0011): the verify function `pf_tls_send` installs in
  /// OpenSSL, driven offline with `PinningFixtures` -- the same cases as `PinningTests`' SecTrust
  /// ones, at the same fixed time, with only the test root as an anchor and no network.
  @Suite struct LinuxPinningTests {

    /// The leaf + intermediate as a server would send them, checked as `host`. `anchored`: trust
    /// the test root (otherwise no anchor at all, which OpenSSL can't get past).
    private func verify(_ pins: PinSet, host: String = "sync.test", anchored: Bool = true) throws
      -> Bool
    {
      let chain = [try PinningFixtures.der("leaf"), try PinningFixtures.der("int")]
      let root = anchored ? try PinningFixtures.der("root") : nil
      let pinBytes = pins.hashes.flatMap { $0 }
      let lengths = chain.map(\.count)
      let copies = chain.map { [UInt8]($0) }
      return copies[0].withUnsafeBufferPointer { leaf in
        copies[1].withUnsafeBufferPointer { intermediate in
          let certs: [UnsafePointer<UInt8>?] = [leaf.baseAddress, intermediate.baseAddress]
          return (root ?? Data()).withUnsafeBytes { anchor in
            pf_tls_verify_chain(
              certs, lengths, certs.count,
              root == nil ? nil : anchor.bindMemory(to: UInt8.self).baseAddress, anchor.count,
              host, Int64(PinningFixtures.verifyTime.timeIntervalSince1970), pinBytes,
              pins.hashes.count) == 1
          }
        }
      }
    }

    private func pins(_ base64: String...) throws -> PinSet { try PinSet(base64: base64) }

    @Test func aPinnedCertificateAnywhereInTheChainPasses() throws {
      for pin in [
        PinningFixtures.intermediatePin, PinningFixtures.rootPin, PinningFixtures.leafPin,
      ] {
        #expect(try verify(try pins(pin)), "\(pin)")
      }
      #expect(try verify(try pins(PinningFixtures.unrelatedPin, PinningFixtures.intermediatePin)))
    }

    @Test func aTrustedChainWithNoPinnedKeyFails() throws {
      #expect(try !verify(try pins(PinningFixtures.unrelatedPin)))
      #expect(try !verify(.none), "an empty pin set trusts nothing")
    }

    @Test func aPinnedKeyDoesNotRescueAnUntrustedChain() throws {
      let all = try pins(
        PinningFixtures.intermediatePin, PinningFixtures.rootPin, PinningFixtures.leafPin)
      #expect(try !verify(all, anchored: false), "unknown root")
      #expect(try !verify(all, host: "other.test"), "wrong host")
    }

    @Test func garbageInputIsRefusedNotTrusted() throws {
      let pins = try pins(PinningFixtures.intermediatePin)
      let junk: [UInt8] = [0x30, 0x82, 0xFF, 0xFF]
      let trusted = junk.withUnsafeBufferPointer { bytes in
        let certs: [UnsafePointer<UInt8>?] = [bytes.baseAddress]
        return pf_tls_verify_chain(
          certs, [junk.count], 1, nil, 0, "sync.test", 0, pins.hashes.flatMap { $0 }, 1)
      }
      #expect(trusted == 0)
      #expect(pf_tls_verify_chain(nil, nil, 0, nil, 0, "sync.test", 0, nil, 0) == 0)
    }
  }
#endif
