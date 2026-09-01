import Foundation
import Testing

@testable import PassFortVault

@Suite struct PayloadCodecTests {

  private func sampleURL() throws -> URL {
    try #require(URL(string: "https://github.com/login"))
  }

  private func fullPayload() throws -> AccountPayload {
    AccountPayload(
      schemaVersion: 1,
      title: "GitHub",
      username: "csaba",
      password: "correct horse battery staple",
      email: "me@example.com",
      urls: [try sampleURL()],
      notes: "personal + work; 2FA on",
      totp: TOTPConfig(secret: Data([1, 2, 3, 4]), digits: 6, period: 30, issuer: "GitHub"),
      securityQuestions: [SecurityQuestion(question: "First pet?", answer: "Rex")],
      memorableWord: "bluebird",
      recoveryCodes: ["aaaa-bbbb", "cccc-dddd"],
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      passwordChangedAt: Date(timeIntervalSince1970: 1_710_000_000),
      passwordHistory: [
        PasswordHistoryEntry(
          password: "old-one", replacedAt: Date(timeIntervalSince1970: 1_695_000_000))
      ],
      category: .login,
      tags: ["dev", "work"],
      favorite: true,
      strength: PasswordStrength(score: 4, guessesLog10: 12.5),
      breach: .clear(checkedAt: Date(timeIntervalSince1970: 1_712_000_000)),
      customFields: [CustomField(label: "Account #", value: "12345", kind: .text)])
  }

  @Test func fullPayloadRoundTripsEqual() throws {
    let payload = try fullPayload()
    let encoded = try PayloadCodec.encode(payload)
    #expect(encoded.count % 256 == 0)
    #expect(try PayloadCodec.decode(encoded) == payload)
  }

  @Test func minimalPayloadRoundTrips() throws {
    let payload = AccountPayload(title: "just a note", createdAt: Date(timeIntervalSince1970: 1))
    #expect(try PayloadCodec.decode(try PayloadCodec.encode(payload)) == payload)
  }

  @Test func unknownKeysArePreserved() throws {
    var payload = AccountPayload(title: "x", createdAt: Date(timeIntervalSince1970: 1))
    payload.unknown = [
      "future_string": .string("hello"),
      "future_number": .number(42),
      "future_object": .object(["nested": .bool(true)]),
    ]
    let decoded = try PayloadCodec.decode(try PayloadCodec.encode(payload))
    #expect(decoded.unknown == payload.unknown)
  }

  @Test func encodingIsDeterministic() throws {
    let payload = try fullPayload()
    #expect(try PayloadCodec.encode(payload) == PayloadCodec.encode(payload))
  }

  @Test func paddingAlwaysReachesABucketBoundary() throws {
    for length in [0, 1, 250, 256, 257, 5000] {
      let payload = AccountPayload(
        title: String(repeating: "n", count: length),
        createdAt: Date(timeIntervalSince1970: 1))
      #expect(try PayloadCodec.encode(payload).count % 256 == 0)
    }
  }

  @Test func truncatedInputThrows() throws {
    #expect(throws: PayloadCodec.Failure.truncated) { try PayloadCodec.decode(Data([0, 0])) }
    #expect(throws: PayloadCodec.Failure.truncated) {
      try PayloadCodec.decode(Data([0, 0, 0, 200]) + Data(count: 10))
    }
  }
}
