import Foundation

/// How to generate a passphrase: words drawn uniformly from the EFF large word list
/// (`EFFWordList`, 7,776 words, about 12.9 bits each), joined by a separator.
///
/// The sibling of `PasswordPolicy`, for a secret a human types or reads aloud: five words
/// (about 65 bits) beat a 12-character random password and are far easier to transcribe.
/// Generation draws from a caller-supplied `RandomNumberGenerator` (the system CSPRNG by
/// default) so tests can seed it.
public struct PassphrasePolicy: Sendable, Equatable, Codable {
  /// How many words. Must be in `1...64`.
  public var wordCount: Int
  /// Put between the words. May be empty.
  public var separator: String
  /// Capitalize each word's first letter: `Abacus-Zoom`. Adds no entropy, but satisfies a site
  /// that insists on an uppercase letter.
  public var capitalize: Bool
  /// Append one random digit to one random word: `abacus-zoom7`. For a site that insists on a
  /// digit.
  public var includeDigit: Bool

  public init(
    wordCount: Int = 5,
    separator: String = "-",
    capitalize: Bool = false,
    includeDigit: Bool = false
  ) {
    self.wordCount = wordCount
    self.separator = separator
    self.capitalize = capitalize
    self.includeDigit = includeDigit
  }

  enum CodingKeys: String, CodingKey {
    case wordCount = "word_count"
    case separator, capitalize
    case includeDigit = "include_digit"
  }

  public enum Failure: Error, Equatable {
    /// `wordCount` is outside `1...64`.
    case invalidWordCount
  }

  /// The words a passphrase is drawn from.
  public static var wordList: [String] { EFFWordList.words }
}

// MARK: - Generation

extension PassphrasePolicy {
  private func validate() throws {
    guard (1...64).contains(wordCount) else { throw Failure.invalidWordCount }
  }

  /// Generate a passphrase using the platform CSPRNG.
  public func generate() throws -> String {
    var rng = SystemRandomNumberGenerator()
    return try generate(using: &rng)
  }

  /// Generate a passphrase from `rng`: `wordCount` independent uniform picks (repeats allowed,
  /// as with dice), then the optional capital and digit.
  public func generate<G: RandomNumberGenerator>(using rng: inout G) throws -> String {
    try validate()
    let list = Self.wordList
    var words = (0..<wordCount).map { _ in list[Int.random(in: 0..<list.count, using: &rng)] }
    if capitalize {
      words = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
    if includeDigit {
      let index = Int.random(in: 0..<words.count, using: &rng)
      words[index] += String(Int.random(in: 0...9, using: &rng))
    }
    return words.joined(separator: separator)
  }

  /// `wordCount * log2(7776)`, plus `log2(10 * wordCount)` for the digit (which digit, on which
  /// word). Exact for the uniform draw; capitalizing is deterministic and adds nothing. Throws
  /// the same `Failure`s as `generate`.
  public func entropyBits() throws -> Double {
    try validate()
    var bits = Double(wordCount) * log2(Double(Self.wordList.count))
    if includeDigit { bits += log2(10 * Double(wordCount)) }
    return bits
  }
}
