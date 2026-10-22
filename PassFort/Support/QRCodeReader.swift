import CoreImage
import Foundation

/// Reads QR codes out of an image file — for an authenticator setup QR saved or screenshotted from
/// a website. Core Image's detector, entirely on device; the image never leaves the Mac.
enum QRCodeReader {
  /// Every QR payload found in the image at `url`, in detection order. Empty when the file is not
  /// an image or holds no QR code.
  static func messages(inImageAt url: URL) -> [String] {
    guard let image = CIImage(contentsOf: url) else { return [] }
    return messages(in: image)
  }

  static func messages(in image: CIImage) -> [String] {
    let detector = CIDetector(
      ofType: CIDetectorTypeQRCode, context: nil,
      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    return (detector?.features(in: image) ?? [])
      .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
  }

  /// The first payload that is an `otpauth://` URI — what the account form wants.
  static func otpauthURI(inImageAt url: URL) -> String? {
    messages(inImageAt: url).first { $0.lowercased().hasPrefix("otpauth://") }
  }
}
