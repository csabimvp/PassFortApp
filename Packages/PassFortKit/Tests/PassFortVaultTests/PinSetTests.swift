import Foundation
import Testing

@testable import PassFortVault

/// `Fixtures/pinning`: a throwaway root -> intermediate -> leaf chain for `sync.test`, whose
/// expected pins were computed with OpenSSL (see its README), not by the code under test. Shared
/// by the pin-set tests here and the two platforms' decision tests (`PinningTests` with SecTrust,
/// `LinuxPinningTests` with OpenSSL).
enum PinningFixtures {
  static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appending(path: "Fixtures/pinning")

  static let rootPin = "wYv+2XJZODvpQGEdrdNF/YPobcweZUdlpXSz8PnQbcU="
  static let intermediatePin = "M1AWPj3AZEniRAxIO4lxAIEtRyVX2LOoj7MHpuzGpDU="
  static let leafPin = "PCClOeEVI70kyhMRHlM0Ey9Ab6qASnZCpuismnykSMg="
  static let unrelatedPin = "ZfrT1aasVhxA4K/WebS2zC/1ET4G9W9rBgbWcHqHchQ="

  /// Inside the leaf's validity: 2027-01-15.
  static let verifyTime = Date(timeIntervalSince1970: 1_800_000_000)

  static func der(_ name: String) throws -> Data {
    try Data(contentsOf: dir.appending(path: "\(name).der"))
  }
}

/// The pin set, the SPKI hash and the loopback rule (m5-sync.md 7.3), on every platform: the hash
/// is CryptoKit's SHA-256 on Apple and libcrypto's on Linux (`PlatformCrypto`).
@Suite struct PinSetTests {

  // MARK: - The SPKI hash

  @Test func spkiHashesMatchOpenSSL() throws {
    let expected = [
      ("root", PinningFixtures.rootPin), ("int", PinningFixtures.intermediatePin),
      ("leaf", PinningFixtures.leafPin),
    ]
    for (name, pin) in expected {
      let hash = try #require(PinSet.spkiHash(of: try PinningFixtures.der(name)))
      #expect(hash.base64EncodedString() == pin, "\(name)")
    }
  }

  @Test func garbageIsNotACertificate() {
    #expect(PinSet.spkiHash(of: Data()) == nil)
    #expect(PinSet.spkiHash(of: Data([0x30, 0x82, 0xFF, 0xFF])) == nil)
    #expect(PinSet.spkiHash(of: Data(repeating: 0x30, count: 64)) == nil)
  }

  // MARK: - Loopback and the pin set

  @Test func onlyThisMachineSkipsPinning() {
    for host in ["localhost", "LOCALHOST", "127.0.0.1", "::1", "[::1]"] {
      #expect(PinSet.isLoopback(host: host), "\(host)")
    }
    let remote: [String?] = ["sync.test", "127.0.0.2", "10.0.0.1", "localhost.evil.test", "", nil]
    for host in remote {
      #expect(!PinSet.isLoopback(host: host), "\(host ?? "nil")")
    }
  }

  @Test func pinsMustBeBase64SHA256s() throws {
    #expect(try PinSet(base64: [" \(PinningFixtures.leafPin)\n"]).hashes.count == 1)
    #expect(throws: PinSet.InvalidPin.self) { try PinSet(base64: ["not base64"]) }
    #expect(throws: PinSet.InvalidPin.self) {
      try PinSet(base64: [Data(count: 20).base64EncodedString()])
    }
  }
}
