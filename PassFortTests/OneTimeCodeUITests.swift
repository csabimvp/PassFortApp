import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PassFortVault
import Testing

@testable import PassFort

/// The app-side one-time-code helpers: reading a setup QR from an image file, and the display
/// grouping. The code generation itself is known-answer tested in `OneTimeCodeTests`.
struct OneTimeCodeUITests {

  private func writeQRImage(_ message: String, to url: URL) throws {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(message.utf8)
    let image = try #require(filter.outputImage).transformed(by: .init(scaleX: 8, y: 8))
    let rep = NSCIImageRep(ciImage: image)
    let ns = NSImage(size: rep.size)
    ns.addRepresentation(rep)
    let tiff = try #require(ns.tiffRepresentation)
    let png = try #require(
      NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: url)
  }

  @Test func readsAnOtpauthURIFromAQRImage() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "pf-qr-\(UUID()).png")
    defer { try? FileManager.default.removeItem(at: url) }
    let uri = "otpauth://totp/GitHub:me?secret=JBSWY3DPEHPK3PXP&issuer=GitHub"
    try writeQRImage(uri, to: url)

    #expect(QRCodeReader.otpauthURI(inImageAt: url) == uri)
    #expect(
      try TOTPConfig(parsing: #require(QRCodeReader.otpauthURI(inImageAt: url))).issuer == "GitHub")
  }

  @Test func aQRThatIsNotAnAuthenticatorSetupIsIgnored() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "pf-qr-\(UUID()).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try writeQRImage("https://example.com", to: url)

    #expect(QRCodeReader.otpauthURI(inImageAt: url) == nil)
  }

  @Test func aNonImageYieldsNothing() {
    let url = FileManager.default.temporaryDirectory.appending(path: "pf-nope-\(UUID()).png")
    #expect(QRCodeReader.messages(inImageAt: url).isEmpty)
  }

  @Test func codesAreGroupedInTheMiddle() {
    #expect(OneTimeCodeRow.grouped("123456") == "123 456")
    #expect(OneTimeCodeRow.grouped("12345678") == "1234 5678")
  }
}
