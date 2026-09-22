import AppKit
import SwiftUI

/// Brand palette, hex only. **This struct is the whole retheme surface** — swap
/// values here and every screen picks it up; nothing else needs to change.
/// `primary` drives buttons/toggles/selection via `.tint(Palette.primary)` at
/// the app root; `accent`/`background` build the window backdrop gradient.
private enum PaletteTokens {
  static let primaryLight = "#F97316"
  static let primaryDark = "#FB923C"

  static let accentLight = "#FB923C"
  static let accentDark = "#F97316"

  static let backgroundLight = "#FFF7ED"
  static let backgroundDark = "#1F140A"
}

enum Palette {
  static let primary = Color(light: PaletteTokens.primaryLight, dark: PaletteTokens.primaryDark)
  static let accent = Color(light: PaletteTokens.accentLight, dark: PaletteTokens.accentDark)
  static let background = Color(
    light: PaletteTokens.backgroundLight, dark: PaletteTokens.backgroundDark)

  static var backgroundGradient: LinearGradient {
    LinearGradient(
      colors: [background, accent.opacity(0.16)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing)
  }
}

extension View {
  /// Applies the brand gradient as a full-bleed backdrop behind the view.
  func pfBackground() -> some View {
    background(Palette.backgroundGradient.ignoresSafeArea())
  }
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
