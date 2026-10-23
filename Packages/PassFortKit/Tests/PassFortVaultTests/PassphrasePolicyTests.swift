import Foundation
import Testing

@testable import PassFortVault

@Suite struct PassphrasePolicyTests {

  /// SplitMix64, as in `PasswordPolicyTests`: a reproducible passphrase in a test.
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

  private let list = Set(PassphrasePolicy.wordList)

  // MARK: - The word list

  /// The list as published: 6^5 distinct lowercase words, 3-9 characters, in order. A broken
  /// literal (a stray blank line, indentation left in) would fail one of these.
  @Test func wordListIsTheEFFLargeList() {
    let words = PassphrasePolicy.wordList
    #expect(words.count == 7776)
    #expect(Set(words).count == 7776)
    #expect(words.first == "abacus")
    #expect(words.last == "zoom")
    #expect(words == words.sorted())
    #expect(words.allSatisfy { (3...9).contains($0.count) })
    #expect(words.allSatisfy { $0.allSatisfy { ("a"..."z").contains($0) || $0 == "-" } })
  }

  // MARK: - Happy path

  @Test func defaultPolicyIsFiveLowercaseWordsJoinedByHyphens() throws {
    let policy = PassphrasePolicy()
    #expect(policy == PassphrasePolicy(wordCount: 5, separator: "-"))
    #expect(!policy.capitalize && !policy.includeDigit)
    // Four list words carry a hyphen of their own ("t-shirt"), so a split can only give more.
    let phrase = try policy.generate()
    #expect(phrase.split(separator: "-").count >= 5)
    #expect(phrase.allSatisfy { ("a"..."z").contains($0) || $0 == "-" })
  }

  @Test func separatorAndWordCountAreHonoured() throws {
    let policy = PassphrasePolicy(wordCount: 8, separator: " ")
    for _ in 0..<200 {
      let words = try policy.generate().split(separator: " ").map(String.init)
      #expect(words.count == 8)
      #expect(words.allSatisfy { list.contains($0) })
    }
  }

  @Test func emptySeparatorRunsTheWordsTogether() throws {
    let phrase = try PassphrasePolicy(wordCount: 3, separator: "", capitalize: true).generate()
    #expect(phrase.filter(\.isUppercase).count == 3)
    #expect(!phrase.contains(" "))
  }

  @Test func capitalizeUppercasesEachWordsFirstLetterOnly() throws {
    let policy = PassphrasePolicy(wordCount: 6, separator: " ", capitalize: true)
    for _ in 0..<200 {
      for word in try policy.generate().split(separator: " ") {
        #expect(word.first?.isUppercase == true)
        #expect(word.dropFirst().allSatisfy { !$0.isUppercase })
        #expect(list.contains(word.lowercased()))
      }
    }
  }

  @Test func includeDigitAddsExactlyOneDigitAtTheEndOfOneWord() throws {
    let policy = PassphrasePolicy(wordCount: 4, separator: " ", includeDigit: true)
    for _ in 0..<200 {
      let words = try policy.generate().split(separator: " ").map(String.init)
      #expect(words.count == 4)
      #expect(words.joined().filter(\.isNumber).count == 1)
      let withDigit = words.filter { $0.last?.isNumber == true }
      #expect(withDigit.count == 1)
      #expect(withDigit.allSatisfy { list.contains(String($0.dropLast())) })
    }
  }

  @Test func seededGenerationIsReproducible() throws {
    let policy = PassphrasePolicy(capitalize: true, includeDigit: true)
    var a = SeededRNG(seed: 42)
    var b = SeededRNG(seed: 42)
    #expect(try policy.generate(using: &a) == policy.generate(using: &b))
  }

  // MARK: - Entropy

  @Test func entropyIsWordCountTimesLog2OfTheListSize() throws {
    let perWord = log2(7776.0)
    #expect(abs(try PassphrasePolicy(wordCount: 5).entropyBits() - 5 * perWord) < 1e-9)
    #expect(
      abs(try PassphrasePolicy(wordCount: 5, capitalize: true).entropyBits() - 5 * perWord)
        < 1e-9)
    #expect(
      abs(
        try PassphrasePolicy(wordCount: 5, includeDigit: true).entropyBits()
          - (5 * perWord + log2(50))) < 1e-9)
  }

  // MARK: - Rejection

  @Test(arguments: [0, -1, 65])
  func outOfRangeWordCountIsRejected(count: Int) {
    let policy = PassphrasePolicy(wordCount: count)
    #expect(throws: PassphrasePolicy.Failure.invalidWordCount) { try policy.generate() }
    #expect(throws: PassphrasePolicy.Failure.invalidWordCount) { try policy.entropyBits() }
  }

  @Test func policyRoundTripsThroughJSON() throws {
    let policy = PassphrasePolicy(
      wordCount: 7, separator: ".", capitalize: true, includeDigit: true)
    let data = try JSONEncoder().encode(policy)
    #expect(try JSONDecoder().decode(PassphrasePolicy.self, from: data) == policy)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("word_count") && json.contains("include_digit"))
  }
}
