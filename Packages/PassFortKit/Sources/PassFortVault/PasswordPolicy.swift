import Foundation

/// Rules for generating a random password — used by `passfort-cli gen`,
/// `add --generate-password`, and (M3) the account form's "Generate" button.
///
/// Pure Swift, drawing from `SystemRandomNumberGenerator` — the platform CSPRNG,
/// the same source `RecoveryKey.generate()` uses. A generated password is **not**
/// key material, and it lands in unwipeable Swift memory regardless (§3.4), so
/// there is nothing to gain by generating it in C++. `RandomNumberGenerator` is a
/// parameter on the core method so tests can pin a seed.
public struct PasswordPolicy: Sendable, Equatable, Codable {
  /// Total length. Must be in `1...1024`.
  public var length: Int
  public var lowercase: Bool
  public var uppercase: Bool
  public var digits: Bool
  public var symbols: Bool
  /// The symbol alphabet. The default avoids quotes, backslash, backtick and
  /// space — the characters that make a password painful to paste into a shell
  /// or a CSV.
  public var symbolSet: String
  /// Drop visually confusable characters (`0 O 1 l I`). On by default: it costs a
  /// little entropy per character and buys a password a human can transcribe.
  public var excludeAmbiguous: Bool
  /// "At least this many" from each **enabled** class. A disabled class's minimum
  /// is ignored. The enabled minimums must sum to `<= length`.
  public var minLowercase: Int
  public var minUppercase: Int
  public var minDigits: Int
  public var minSymbols: Int

  public init(
    length: Int = 20,
    lowercase: Bool = true,
    uppercase: Bool = true,
    digits: Bool = true,
    symbols: Bool = true,
    symbolSet: String = "!@#$%^&*()-_=+[]{};:,.?",
    excludeAmbiguous: Bool = true,
    minLowercase: Int = 1,
    minUppercase: Int = 1,
    minDigits: Int = 1,
    minSymbols: Int = 1
  ) {
    self.length = length
    self.lowercase = lowercase
    self.uppercase = uppercase
    self.digits = digits
    self.symbols = symbols
    self.symbolSet = symbolSet
    self.excludeAmbiguous = excludeAmbiguous
    self.minLowercase = minLowercase
    self.minUppercase = minUppercase
    self.minDigits = minDigits
    self.minSymbols = minSymbols
  }

  enum CodingKeys: String, CodingKey {
    case length, lowercase, uppercase, digits, symbols
    case symbolSet = "symbol_set"
    case excludeAmbiguous = "exclude_ambiguous"
    case minLowercase = "min_lowercase"
    case minUppercase = "min_uppercase"
    case minDigits = "min_digits"
    case minSymbols = "min_symbols"
  }

  public enum Failure: Error, Equatable {
    /// `length` is outside `1...1024`.
    case invalidLength
    /// Every character class is disabled.
    case noCharacterClasses
    /// An enabled class has no usable characters (an empty `symbolSet`, or every
    /// character filtered out as ambiguous).
    case emptyAlphabet
    /// The enabled classes' minimums sum to more than `length`.
    case lengthTooShortForMinimums
  }
}

// MARK: - Generation

extension PasswordPolicy {
  /// Characters that look alike in most fonts.
  public static let ambiguousCharacters: Set<Character> = ["0", "O", "1", "l", "I"]

  private static let lowercaseAlphabet = Array("abcdefghijklmnopqrstuvwxyz")
  private static let uppercaseAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
  private static let digitAlphabet = Array("0123456789")

  private struct CharacterClass {
    let alphabet: [Character]
    let minimum: Int
  }

  /// Validate the policy and resolve the per-class alphabets (ambiguous filter
  /// applied) plus their union. Throws a `Failure` if the policy can't produce a
  /// password.
  private func resolved() throws -> (classes: [CharacterClass], union: [Character]) {
    guard (1...1024).contains(length) else { throw Failure.invalidLength }

    func filtered(_ characters: [Character]) -> [Character] {
      excludeAmbiguous
        ? characters.filter { !Self.ambiguousCharacters.contains($0) }
        : characters
    }

    var classes: [CharacterClass] = []
    func enable(_ on: Bool, _ alphabet: [Character], min: Int) {
      guard on else { return }
      classes.append(.init(alphabet: filtered(alphabet), minimum: max(0, min)))
    }
    enable(lowercase, Self.lowercaseAlphabet, min: minLowercase)
    enable(uppercase, Self.uppercaseAlphabet, min: minUppercase)
    enable(digits, Self.digitAlphabet, min: minDigits)
    if symbols {
      var seen = Set<Character>()
      let deduped = filtered(Array(symbolSet)).filter { seen.insert($0).inserted }
      classes.append(.init(alphabet: deduped, minimum: max(0, minSymbols)))
    }

    guard !classes.isEmpty else { throw Failure.noCharacterClasses }
    guard classes.allSatisfy({ !$0.alphabet.isEmpty }) else { throw Failure.emptyAlphabet }
    guard classes.reduce(0, { $0 + $1.minimum }) <= length else {
      throw Failure.lengthTooShortForMinimums
    }

    let union = Array(Set(classes.flatMap(\.alphabet))).sorted()
    return (classes, union)
  }

  /// Generate a password using the platform CSPRNG.
  public func generate() throws -> String {
    var rng = SystemRandomNumberGenerator()
    return try generate(using: &rng)
  }

  /// Generate a password from `rng`. Every enabled class contributes at least its
  /// minimum; the remainder is drawn uniformly from the union of the enabled
  /// alphabets; the result is then shuffled so the guaranteed characters aren't
  /// clustered at the front.
  public func generate<G: RandomNumberGenerator>(using rng: inout G) throws -> String {
    let (classes, union) = try resolved()

    var characters: [Character] = []
    characters.reserveCapacity(length)
    for characterClass in classes {
      for _ in 0..<characterClass.minimum {
        characters.append(Self.pick(from: characterClass.alphabet, using: &rng))
      }
    }
    while characters.count < length {
      characters.append(Self.pick(from: union, using: &rng))
    }
    characters.shuffle(using: &rng)
    return String(characters)
  }

  /// `length * log2(alphabet size)` — exact for a uniform-random password. The
  /// per-class minimums pull the true value very slightly below this; it is a
  /// useful, honest lower bound. Throws the same `Failure`s as `generate`.
  public func entropyBits() throws -> Double {
    let (_, union) = try resolved()
    return Double(length) * log2(Double(union.count))
  }

  /// Uniform pick by index — avoids `randomElement()!` (`alphabet` is non-empty by
  /// construction, checked in `resolved()`).
  private static func pick<G: RandomNumberGenerator>(
    from alphabet: [Character], using rng: inout G
  ) -> Character {
    alphabet[Int.random(in: 0..<alphabet.count, using: &rng)]
  }
}
