import Foundation
import Testing

@testable import PassFortVault

@Suite struct PasswordPolicyTests {

  /// SplitMix64 — a deterministic RNG so a generated password is reproducible in
  /// a test. Never used outside tests.
  private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  private let lower = Set("abcdefghijklmnopqrstuvwxyz")
  private let upper = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
  private let digit = Set("0123456789")

  // MARK: - Happy path

  @Test func defaultPolicyHonoursLengthAndEveryClass() throws {
    let policy = PasswordPolicy()
    for _ in 0..<200 {
      let pw = try policy.generate()
      #expect(pw.count == 20)
      #expect(pw.contains { lower.contains($0) })
      #expect(pw.contains { upper.contains($0) })
      #expect(pw.contains { digit.contains($0) })
      #expect(pw.contains { !$0.isLetter && !$0.isNumber })  // a symbol
    }
  }

  @Test func minimumsAreHonoured() throws {
    let policy = PasswordPolicy(length: 24, minDigits: 6, minSymbols: 4)
    for _ in 0..<200 {
      let pw = try policy.generate()
      #expect(pw.count == 24)
      #expect(pw.filter { digit.contains($0) }.count >= 6)
      #expect(pw.filter { !$0.isLetter && !$0.isNumber }.count >= 4)
    }
  }

  @Test func disabledClassesNeverAppear() throws {
    let policy = PasswordPolicy(length: 40, uppercase: false, symbols: false)
    let allowed = lower.union(digit)
    for _ in 0..<200 {
      let pw = try policy.generate()
      #expect(pw.allSatisfy { allowed.contains($0) })
    }
  }

  @Test func excludeAmbiguousRemovesConfusables() throws {
    let policy = PasswordPolicy(length: 64, symbols: false, excludeAmbiguous: true)
    for _ in 0..<200 {
      let pw = try policy.generate()
      #expect(pw.allSatisfy { !PasswordPolicy.ambiguousCharacters.contains($0) })
    }
  }

  @Test func allowingAmbiguousEventuallyEmitsThem() throws {
    // digits only, no ambiguous filter: over a big sample a '0' or '1' must show up.
    let policy = PasswordPolicy(
      length: 64, lowercase: false, uppercase: false, symbols: false, excludeAmbiguous: false,
      minLowercase: 0, minUppercase: 0, minSymbols: 0)
    var seenAmbiguous = false
    for _ in 0..<50 where !seenAmbiguous {
      seenAmbiguous = try policy.generate().contains { $0 == "0" || $0 == "1" }
    }
    #expect(seenAmbiguous)
  }

  @Test func everyCharacterComesFromTheConfiguredAlphabet() throws {
    let policy = PasswordPolicy(length: 50, symbolSet: "!#$%")
    let allowed = lower.union(upper).union(digit).union("!#$%")
      .subtracting(PasswordPolicy.ambiguousCharacters)
    for _ in 0..<200 {
      #expect(try policy.generate().allSatisfy { allowed.contains($0) })
    }
  }

  // MARK: - Determinism

  @Test func aSeededGeneratorIsReproducible() throws {
    let policy = PasswordPolicy()
    var a = SeededRNG(seed: 0xDEAD_BEEF)
    var b = SeededRNG(seed: 0xDEAD_BEEF)
    var c = SeededRNG(seed: 0x0001_0002)
    #expect(try policy.generate(using: &a) == policy.generate(using: &b))
    #expect(try policy.generate(using: &a) != policy.generate(using: &c))
  }

  // MARK: - Entropy

  @Test func entropyMatchesAlphabetSize() throws {
    // lowercase only, ambiguous allowed -> 26-symbol alphabet.
    let policy = PasswordPolicy(
      length: 10, uppercase: false, digits: false, symbols: false, excludeAmbiguous: false,
      minUppercase: 0, minDigits: 0, minSymbols: 0)
    #expect(abs(try policy.entropyBits() - 10 * log2(26)) < 0.0001)
  }

  // MARK: - Rejected policies

  @Test func rejectsImpossiblePolicies() {
    #expect(throws: PasswordPolicy.Failure.noCharacterClasses) {
      let allOff = PasswordPolicy(
        lowercase: false, uppercase: false, digits: false, symbols: false)
      try allOff.generate()
    }
    #expect(throws: PasswordPolicy.Failure.lengthTooShortForMinimums) {
      try PasswordPolicy(length: 3).generate()  // 4 classes x min 1
    }
    #expect(throws: PasswordPolicy.Failure.invalidLength) {
      try PasswordPolicy(length: 0).generate()
    }
    #expect(throws: PasswordPolicy.Failure.invalidLength) {
      try PasswordPolicy(length: 2048).generate()
    }
    #expect(throws: PasswordPolicy.Failure.emptyAlphabet) {
      try PasswordPolicy(
        lowercase: false, uppercase: false, digits: false, symbols: true, symbolSet: "",
        minSymbols: 0
      ).generate()
    }
  }

  // MARK: - Codable

  @Test func roundTripsThroughJSONWithSnakeCaseKeys() throws {
    let policy = PasswordPolicy(length: 32, symbols: false, excludeAmbiguous: false, minDigits: 4)
    let data = try JSONEncoder().encode(policy)
    #expect(String(decoding: data, as: UTF8.self).contains("\"exclude_ambiguous\""))
    #expect(try JSONDecoder().decode(PasswordPolicy.self, from: data) == policy)
  }
}
