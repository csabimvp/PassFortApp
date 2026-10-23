import Foundation
import Testing

@testable import PassFortVault

/// `DeviceIdentity` (m5-sync.md A.5): created once, kept, never silently replaced.
@Suite struct DeviceIdentityTests {

  private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "pf-device-\(UUID().uuidString)/nested/device.json")
  }

  @Test func createsOnceThenReadsTheSameIdentityBack() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let created = try DeviceIdentity.loadOrCreate(at: url, name: "Test Mac")
    #expect(created.name == "Test Mac")
    let again = try DeviceIdentity.loadOrCreate(at: url, name: "a different name")
    #expect(again == created, "the stored identity wins; the name is only for a new one")

    let path = url.path(percentEncoded: false)
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  }

  @Test func neverReplacesAFileItCannotRead() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)

    #expect(throws: (any Error).self) { try DeviceIdentity.loadOrCreate(at: url, name: "x") }
    #expect(try Data(contentsOf: url) == Data("not json".utf8))
  }

  @Test func twoInstallsGetTwoIdentities() throws {
    let a = tempURL()
    let b = tempURL()
    defer {
      try? FileManager.default.removeItem(at: a.deletingLastPathComponent())
      try? FileManager.default.removeItem(at: b.deletingLastPathComponent())
    }
    #expect(
      try DeviceIdentity.loadOrCreate(at: a, name: "x").id
        != DeviceIdentity.loadOrCreate(at: b, name: "x").id)
  }
}
