import AppKit
import SwiftUI

/// Brand palette. The values live in `UI/tokens.json`, generated into `PaletteTokens.swift` by
/// `scripts/gen_palette.swift`: **that JSON file is the whole retheme surface**, so change it there
/// and every screen picks it up. `primary` drives buttons/toggles/selection via
/// `.tint(Palette.primary)` at the app root. Windows use the system background; there is no brand
/// backdrop.
enum Palette {
  static let primary = Color(PaletteTokens.brand)
  static let success = Color(PaletteTokens.success)
  /// Amber, deliberately not orange: orange means PassFort, never "something is wrong".
  static let warning = Color(PaletteTokens.warning)
  static let danger = Color(PaletteTokens.danger)
  /// The favorite star: gold, a step brighter than `warning` so a star never reads as an alert.
  static let favorite = Color(PaletteTokens.favorite)

  /// A category family at full strength — a glyph, a sidebar icon.
  static func color(_ family: PaletteFamily) -> Color {
    Color(family.hex)
  }

  /// A category family as a faint fill, behind a glyph drawn in `color(_:)`.
  static func tint(_ family: PaletteFamily) -> Color {
    Color(
      family.hex, lightAlpha: PaletteTokens.tileLightAlpha,
      darkAlpha: PaletteTokens.tileDarkAlpha)
  }
}

/// A colour as `"#RRGGBB"` strings for Aqua and Dark Aqua.
struct HexPair: Sendable {
  let light: String
  let dark: String
}

// MARK: - Hex-driven, appearance-aware Color

extension Color {
  /// A `Color` that resolves to `pair.light` in Aqua and `pair.dark` in Dark Aqua, at the given
  /// opacity in each, no asset catalog entry required.
  init(_ pair: HexPair, lightAlpha: Double = 1, darkAlpha: Double = 1) {
    let dynamic = NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      let color = NSColor(hex: isDark ? pair.dark : pair.light) ?? .black
      return color.withAlphaComponent(isDark ? darkAlpha : lightAlpha)
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
