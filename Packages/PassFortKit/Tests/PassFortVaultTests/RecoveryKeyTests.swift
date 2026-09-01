import Foundation
import Testing

@testable import PassFortVault

@Suite struct RecoveryKeyTests {

  // MARK: - Crockford Base32

  @Test func encodeDecodeRoundTripsArbitraryBytes() throws {
    for _ in 0..<50 {
      let bytes = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
      let text = CrockfordBase32.encode(bytes)
      #expect(text.count == 52)  // 256 bits / 5, rounded up
      #expect(try CrockfordBase32.decode(text, outputByteCount: 32) == bytes)
    }
  }

  @Test func decodeIsTolerantOfCaseSeparatorsAndAmbiguousGlyphs() throws {
    let bytes = Data((0..<32).map { UInt8($0) })
    let canonical = CrockfordBase32.encode(bytes)

    // Lowercase, spaced, hyphenated -- all decode identically.
    let messy = canonical.lowercased().enumerated().map { i, c in
      i % 4 == 3 ? "\(c)-" : "\(c)"
    }.joined()
    #expect(try CrockfordBase32.decode(messy, outputByteCount: 32) == bytes)

    // O -> 0 and I/L -> 1 substitutions a human might write.
    let substituted = canonical.replacingOccurrences(of: "0", with: "O")
      .replacingOccurrences(of: "1", with: "l")
    #expect(try CrockfordBase32.decode(substituted, outputByteCount: 32) == bytes)
  }

  @Test func decodeRejectsAnUnknownSymbol() {
    #expect(throws: CrockfordBase32.Failure.unknownSymbol("U")) {
      try CrockfordBase32.decode("ABCU", outputByteCount: 2)  // U is not a data symbol
    }
  }

  @Test func checkSymbolCatchesAOneSymbolSlip() throws {
    let bytes = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
    let key = try RecoveryKey(raw: bytes)
    var symbols = Array(key.grouped)

    // Flip the first data symbol to a different one.
    let firstDataIndex = try #require(symbols.firstIndex { $0 != "-" })
    symbols[firstDataIndex] = symbols[firstDataIndex] == "0" ? "1" : "0"

    #expect(throws: RecoveryKey.Failure.malformed) {
      try RecoveryKey(grouped: String(symbols))
    }
  }

  // MARK: - RecoveryKey

  @Test func groupedFormRoundTrips() throws {
    let key = RecoveryKey.generate()
    let parsed = try RecoveryKey(grouped: key.grouped)
    #expect(parsed == key)
    #expect(parsed.raw == key.raw)
  }

  @Test func groupedFormShape() throws {
    let key = try RecoveryKey(raw: Data(count: 32))
    // 13 groups of 4, then "-0" (the check symbol for all-zero is 0).
    #expect(key.grouped == "0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-0")
  }

  @Test func rawMustBe32Bytes() {
    #expect(throws: RecoveryKey.Failure.wrongLength) { try RecoveryKey(raw: Data(count: 31)) }
    #expect(throws: RecoveryKey.Failure.wrongLength) { try RecoveryKey(raw: Data(count: 33)) }
  }

  @Test func generateIsNotConstant() {
    #expect(RecoveryKey.generate() != RecoveryKey.generate())
  }
}
