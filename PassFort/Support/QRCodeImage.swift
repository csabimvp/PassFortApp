import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Draws a QR code -- the join invite in `AddDeviceSheet`. Core Image's generator, on device.
enum QRCodeImage {
  /// `message` as a QR code, each module `scale` pixels square, with medium error correction.
  /// `nil` if the message is too long for a QR code.
  static func make(_ message: String, scale: CGFloat = 8) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(message.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    return CIContext().createCGImage(scaled, from: scaled.extent)
  }
}
