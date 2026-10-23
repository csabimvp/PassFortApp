import Foundation
import PassFortVault
import Testing

@testable import PassFort

/// The generator's choices, without the view: what each kind of request produces, and that the
/// options the checkboxes allow can never make an impossible policy.
@MainActor
struct PasswordGeneratorTests {

  @Test func everyCheckboxCombinationGeneratesAtTheRequestedLength() {
    for uppercase in [false, true] {
      for digits in [false, true] {
        for symbols in [false, true] {
          for excludeAmbiguous in [false, true] {
            let request = GeneratorRequest.characters(
              length: 12, uppercase: uppercase, digits: digits, symbols: symbols,
              excludeAmbiguous: excludeAmbiguous)
            #expect(request.generate().count == 12)
            #expect(request.entropyBits != nil)
          }
        }
      }
    }
  }

  @Test func charactersAlwaysIncludeLowercase() {
    let request = GeneratorRequest.characters(
      length: 30, uppercase: false, digits: false, symbols: false, excludeAmbiguous: true)
    #expect(request.generate().allSatisfy { $0.isLowercase })
  }

  /// A length stored by the old generator (which went to 128) lands inside the slider's range.
  @Test func lengthAndWordCountAreClampedToTheSliders() {
    let long = GeneratorRequest.characters(
      length: 128, uppercase: true, digits: true, symbols: true, excludeAmbiguous: true)
    #expect(long.generate().count == GeneratorRequest.lengthRange.upperBound)
    let short = GeneratorRequest.characters(
      length: 2, uppercase: true, digits: true, symbols: true, excludeAmbiguous: true)
    #expect(short.generate().count == GeneratorRequest.lengthRange.lowerBound)

    guard
      case .words(let policy) = GeneratorRequest.words(
        count: 40, separator: "-", capitalize: false, digit: false)
    else {
      Issue.record("expected a words request")
      return
    }
    #expect(policy.wordCount == GeneratorRequest.wordRange.upperBound)
  }

  @Test func aTypedNumberAppliesOnlyWhenWholeAndInRange() {
    let range = GeneratorRequest.lengthRange
    #expect(RangeNumberField.parse("32", in: range) == 32)
    #expect(RangeNumberField.parse(" 8 ", in: range) == 8)
    #expect(RangeNumberField.parse("64", in: range) == 64)
    #expect(RangeNumberField.parse("3", in: range) == nil)  // on the way to 32
    #expect(RangeNumberField.parse("65", in: range) == nil)
    #expect(RangeNumberField.parse("", in: range) == nil)
    #expect(RangeNumberField.parse("2x", in: range) == nil)
    #expect(RangeNumberField.parse("-10", in: range) == nil)
  }

  @Test func wordsRequestJoinsWithTheChosenSeparator() {
    let request = GeneratorRequest.words(
      count: 4, separator: PassphraseSeparator.space.rawValue, capitalize: true, digit: true)
    let words = request.generate().split(separator: " ")
    #expect(words.count == 4)
    #expect(words.allSatisfy { $0.first?.isUppercase == true })
    #expect(words.joined().filter(\.isNumber).count == 1)
  }

  @Test func wordsEntropyComesFromThePassphrasePolicy() throws {
    let request = GeneratorRequest.words(count: 5, separator: "-", capitalize: false, digit: false)
    let bits = try #require(request.entropyBits)
    #expect(abs(bits - 5 * log2(7776.0)) < 1e-9)
  }
}
