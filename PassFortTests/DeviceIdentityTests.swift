import Foundation
import Testing

@testable import PassFort

struct DeviceIdentityTests {

  private func uniqueService() -> String { "app.passfort.tests.\(UUID().uuidString)" }

  @Test func theIdIsStableAcrossCalls() {
    let service = uniqueService()
    defer { try? Keychain.delete(service: service, account: "default") }

    #expect(DeviceIdentity.current(service: service) == DeviceIdentity.current(service: service))
  }

  @Test func theIdIsNotTheZeroUUID() {
    let service = uniqueService()
    defer { try? Keychain.delete(service: service, account: "default") }

    #expect(DeviceIdentity.current(service: service) != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
  }

  @Test func accountsGetDifferentIDs() {
    let service = uniqueService()
    defer {
      try? Keychain.delete(service: service, account: "default")
      try? Keychain.delete(service: service, account: "other")
    }

    #expect(
      DeviceIdentity.current(service: service) != DeviceIdentity.current(service: service, account: "other"))
  }

  @Test func aCorruptStoredValueIsReplacedNotTrusted() throws {
    let service = uniqueService()
    defer { try? Keychain.delete(service: service, account: "default") }
    try Keychain.set(Data("not a uuid".utf8), service: service, account: "default")

    let id = DeviceIdentity.current(service: service)
    #expect(DeviceIdentity.current(service: service) == id)
  }
}
