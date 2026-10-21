import AppKit
import SwiftUI

/// Brand palette, hex only. **This struct is the whole retheme surface** — swap
/// values here and every screen picks it up; nothing else needs to change.
/// `primary` drives buttons/toggles/selection via `.tint(Palette.primary)` at
/// the app root. Windows use the system background; there is no brand backdrop.
private enum PaletteTokens {
  static let primaryLight = "#F97316"
  static let primaryDark = "#FB923C"
}

enum Palette {
  static let primary = Color(light: PaletteTokens.primaryLight, dark: PaletteTokens.primaryDark)
}

// MARK: - Hex-driven, appearance-aware Color

extension Color {
  /// A `Color` that resolves to `light` in Aqua and `dark` in Dark Aqua, no
  /// asset catalog entry required. `light`/`dark` are `"#RRGGBB"` strings.
  init(light: String, dark: String) {
    let dynamic = NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      return NSColor(hex: isDark ? dark : light) ?? .black
    }
    self.init(nsColor: dynamic)
  }
}

extension NSColor {
  /// Parses `"#RRGGBB"` (leading `#` optional). `nil` on malformed input.
  convenience init?(hex: String) {
    let stripped = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard stripped.count == 6, let rgb = UInt32(stripped, radix: 16) else { return nil }
    self.init(
      srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: 1)
  }
}
