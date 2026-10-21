import Foundation
import Testing

@testable import PassFort

/// The plain (ungated) `Keychain` variant against the real data-protection keychain, each test under
/// its own throwaway service name. The Touch ID variant needs a finger, so it is a by-hand check.
struct KeychainTests {

  private func uniqueService() -> String { "app.passfort.tests.\(UUID().uuidString)" }

  @Test func aMissingItemReadsAsNil() throws {
    #expect(try Keychain.get(service: uniqueService(), account: "a") == nil)
  }

  @Test func setThenGetRoundTrips() throws {
    let service = uniqueService()
    defer { try? Keychain.delete(service: service, account: "a") }

    try Keychain.set(Data([1, 2, 3]), service: service, account: "a")
    #expect(try Keychain.get(service: service, account: "a") == Data([1, 2, 3]))
  }

  @Test func setReplacesInsteadOfFailingOnADuplicate() throws {
    let service = uniqueService()
    defer { try? Keychain.delete(service: service, account: "a") }

    try Keychain.set(Data([1]), service: service, account: "a")
    try Keychain.set(Data([2, 2]), service: service, account: "a")
    #expect(try Keychain.get(service: service, account: "a") == Data([2, 2]))
  }

  @Test func accountsAreIndependent() throws {
    let service = uniqueService()
    defer {
      try? Keychain.delete(service: service, account: "a")
      try? Keychain.delete(service: service, account: "b")
    }

    try Keychain.set(Data([1]), service: service, account: "a")
    try Keychain.set(Data([2]), service: service, account: "b")
    #expect(try Keychain.get(service: service, account: "a") == Data([1]))
    #expect(try Keychain.get(service: service, account: "b") == Data([2]))
  }

  @Test func deleteRemovesTheItemAndIsIdempotent() throws {
    let service = uniqueService()
    try Keychain.set(Data([9]), service: service, account: "a")

    try Keychain.delete(service: service, account: "a")
    try Keychain.delete(service: service, account: "a")
    #expect(try Keychain.get(service: service, account: "a") == nil)
  }
}
