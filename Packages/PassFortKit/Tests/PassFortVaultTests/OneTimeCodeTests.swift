import Foundation
import Testing

@testable import PassFortVault

@Suite struct OneTimeCodeTests {

  // MARK: - RFC 6238 Appendix B known answers

  /// The RFC's seeds: ASCII "1234567890" repeated to the hash's block-ish length.
  private func seed(_ length: Int) -> Data {
    Data(String(repeating: "1234567890", count: 7).utf8.prefix(length))
  }

  private static let vectors: [(time: TimeInterval, sha1: String, sha256: String, sha512: String)] =
    [
      (59, "94287082", "46119246", "90693936"),
      (1_111_111_109, "07081804", "68084774", "25091201"),
      (1_111_111_111, "14050471", "67062674", "99943326"),
      (1_234_567_890, "89005924", "91819424", "93441116"),
      (2_000_000_000, "69279037", "90698825", "38618901"),
      (20_000_000_000, "65353130", "77737706", "47863826"),
    ]

  @Test func rfc6238KnownAnswers() {
    let sha1 = TOTPConfig(secret: seed(20), algorithm: .sha1, digits: 8)
    let sha256 = TOTPConfig(secret: seed(32), algorithm: .sha256, digits: 8)
    let sha512 = TOTPConfig(secret: seed(64), algorithm: .sha512, digits: 8)
    for vector in Self.vectors {
      let at = Date(timeIntervalSince1970: vector.time)
      #expect(sha1.code(at: at) == vector.sha1, "SHA-1 at \(vector.time)")
      #expect(sha256.code(at: at) == vector.sha256, "SHA-256 at \(vector.time)")
      #expect(sha512.code(at: at) == vector.sha512, "SHA-512 at \(vector.time)")
    }
  }

  @Test func sixDigitCodesKeepLeadingZeros() {
    // The 8-digit answer at 1111111109 is 07081804; its last six digits are the 6-digit code.
    let config = TOTPConfig(secret: seed(20))
    #expect(config.code(at: Date(timeIntervalSince1970: 1_111_111_109)) == "081804")
  }

  @Test func secondsRemainingCountsDownToTheStepBoundary() {
    let config = TOTPConfig(secret: seed(20))
    #expect(config.secondsRemaining(at: Date(timeIntervalSince1970: 60)) == 30)
    #expect(config.secondsRemaining(at: Date(timeIntervalSince1970: 89)) == 1)
  }

  // MARK: - RFC 4648 Base32

  @Test func base32KnownAnswers() {
    let vectors = [
      ("", ""), ("f", "MY"), ("fo", "MZXQ"), ("foo", "MZXW6"), ("foob", "MZXW6YQ"),
      ("fooba", "MZXW6YTB"), ("foobar", "MZXW6YTBOI"),
    ]
    for (plain, encoded) in vectors {
      #expect(Base32.encode(Data(plain.utf8)) == encoded)
      #expect(Base32.decode(encoded) == Data(plain.utf8))
    }
  }

  @Test func base32DecodeIsLenientAboutCaseSpacingAndPadding() {
    #expect(Base32.decode("mzxw 6ytb-oi======") == Data("foobar".utf8))
  }

  @Test func base32RejectsForeignSymbolsAndImpossibleLengths() {
    #expect(Base32.decode("MZXW1") == nil)  // '1' is not in the alphabet
    #expect(Base32.decode("M") == nil)  // one symbol can't make a byte
  }

  // MARK: - otpauth://

  @Test func parsesAFullURI() throws {
    let config = try TOTPConfig(
      parsing:
        "otpauth://totp/ACME%20Co:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME%20Co"
        + "&algorithm=SHA256&digits=8&period=60")
    #expect(config.secret == Base32.decode("JBSWY3DPEHPK3PXP"))
    #expect(config.issuer == "ACME Co")
    #expect(config.label == "alice@example.com")
    #expect(config.algorithm == .sha256)
    #expect(config.digits == 8)
    #expect(config.period == 60)
  }

  @Test func theIssuerFallsBackToTheLabelPrefix() throws {
    let config = try TOTPConfig(parsing: "otpauth://totp/GitHub:me?secret=JBSWY3DPEHPK3PXP")
    #expect(config.issuer == "GitHub")
    #expect(config.label == "me")
    #expect(config.algorithm == .sha1)
    #expect(config.digits == 6)
    #expect(config.period == 30)
  }

  @Test func aBareSecretGetsTheDefaults() throws {
    let config = try TOTPConfig(parsing: "  jbsw y3dp ehpk 3pxp  ")
    #expect(config == TOTPConfig(secret: try #require(Base32.decode("JBSWY3DPEHPK3PXP"))))
  }

  @Test func theURIRoundTrips() throws {
    let original = TOTPConfig(
      secret: seed(20), algorithm: .sha512, digits: 8, period: 45, issuer: "Bank",
      label: "me@example.com")
    #expect(try TOTPConfig(parsing: original.otpauthURI) == original)
  }

  @Test func rejectsWhatItCannotUse() {
    #expect(throws: OneTimeCodeError.counterBasedNotSupported) {
      try TOTPConfig(parsing: "otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP&counter=1")
    }
    #expect(throws: OneTimeCodeError.missingSecret) {
      try TOTPConfig(parsing: "otpauth://totp/x?issuer=y")
    }
    #expect(throws: OneTimeCodeError.badSecret) {
      try TOTPConfig(parsing: "otpauth://totp/x?secret=not!base32")
    }
    #expect(throws: OneTimeCodeError.unsupportedAlgorithm("MD5")) {
      try TOTPConfig(parsing: "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&algorithm=MD5")
    }
    #expect(throws: OneTimeCodeError.badDigits) {
      try TOTPConfig(parsing: "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=4")
    }
    #expect(throws: OneTimeCodeError.badPeriod) {
      try TOTPConfig(parsing: "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&period=0")
    }
    #expect(throws: OneTimeCodeError.unrecognized) {
      try TOTPConfig(parsing: "hunter2!")
    }
  }
}
