#!/usr/bin/env swift
// Draws the README's banner, light and dark, from UI/tokens.json:
//
//   swift scripts/make_readme_art.swift
//
// Writes docs/images/hero-light.svg and docs/images/hero-dark.svg: the app icon and name beside a
// small vault window in the app's palette (category tiles, a strength pill, the code ring). Brand,
// semantic and family colours come from the tokens, so a retheme only needs a re-run. The window's
// neutral surfaces are copied from the design mockups. Foundation only, nothing to
// install. Run from anywhere: paths resolve from this script.

import Foundation

// MARK: - Tokens

struct Pair: Decodable {
  let light: String
  let dark: String
}

struct Family: Decodable {
  let name: String
  let light: String
  let dark: String
}

struct Tokens: Decodable {
  struct Semantic: Decodable {
    let success: Pair
    let danger: Pair
    let favorite: Pair
  }
  struct Tile: Decodable {
    let lightAlpha: Double
    let darkAlpha: Double
  }
  let brand: Pair
  let semantic: Semantic
  let tile: Tile
  let families: [Family]
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("make_readme_art: \(message)\n".utf8))
  exit(1)
}

// MARK: - Theme

/// Every colour one banner uses, resolved for light or dark.
struct Theme {
  let dark: Bool
  let brand: String
  let success: String
  let danger: String
  let star: String
  let family: [String: String]
  let tileAlpha: Double

  // Neutral surfaces, from the design mockups.
  var page: String { dark ? "#161618" : "#F7F7F5" }
  var pageBorder: String { dark ? "#2C2C2E" : "#E5E5E3" }
  var frame: String { dark ? "#3A3A3C" : "#D4D4D2" }
  var sidebar: String { dark ? "#262628" : "#EFEEEC" }
  var sideSelection: String { dark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.07)" }
  var list: String { dark ? "#1E1E1E" : "#FFFFFF" }
  var detail: String { dark ? "#1A1A1C" : "#F5F5F7" }
  var card: String { dark ? "#2C2C2E" : "#FFFFFF" }
  var cardBorder: String { dark ? "#2C2C2E" : "#E6E6E8" }
  var border: String { dark ? "#38383A" : "#E6E6E4" }
  var field: String { dark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.06)" }
  var text: String { dark ? "#F5F5F7" : "#1D1D1F" }
  var text2: String { dark ? "#A1A1A6" : "#636366" }
  var ringTrack: String { dark ? "rgba(255,255,255,0.14)" : "rgba(0,0,0,0.10)" }
  /// List selection: the light-mode brand in both, as the mockup draws it.
  let selection: String
  /// The icon's gradient: dark-mode brand at the top, light-mode brand at the bottom.
  let iconTop: String
  let iconBottom: String

  init(_ tokens: Tokens, dark: Bool) {
    func pick(_ pair: Pair) -> String { dark ? pair.dark : pair.light }
    self.dark = dark
    brand = pick(tokens.brand)
    success = pick(tokens.semantic.success)
    danger = pick(tokens.semantic.danger)
    star = pick(tokens.semantic.favorite)
    family = Dictionary(
      uniqueKeysWithValues: tokens.families.map { ($0.name, dark ? $0.dark : $0.light) })
    tileAlpha = dark ? tokens.tile.darkAlpha : tokens.tile.lightAlpha
    selection = tokens.brand.light
    iconTop = tokens.brand.dark
    iconBottom = tokens.brand.light
  }

  func familyColor(_ name: String) -> String {
    guard let hex = family[name] else { fail("tokens have no \"\(name)\" family") }
    return hex
  }

  func tint(_ hex: String, _ alpha: Double) -> String {
    guard hex.count == 7, hex.hasPrefix("#"), let rgb = Int(hex.dropFirst(), radix: 16) else {
      fail("\"\(hex)\" is not #RRGGBB")
    }
    return "rgba(\((rgb >> 16) & 0xFF),\((rgb >> 8) & 0xFF),\(rgb & 0xFF),\(alpha))"
  }
}

// MARK: - Drawing

let font = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Helvetica, Arial, sans-serif"
let mono = "ui-monospace, 'SF Mono', Menlo, Consolas, monospace"

func escape(_ text: String) -> String {
  text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
}

/// A line of text. `trailing` is raw SVG (a `<tspan>`) that flows on after it, so a star or a
/// coloured word sits right after the text without measuring it.
func text(
  _ string: String, x: Double, y: Double, size: Double, fill: String, weight: Int = 400,
  anchor: String = "start", family: String = font, spacing: Double = 0, trailing: String = ""
) -> String {
  "<text x=\"\(x)\" y=\"\(y)\" font-family=\"\(family)\" font-size=\"\(size)\" "
    + "font-weight=\"\(weight)\" fill=\"\(fill)\" text-anchor=\"\(anchor)\" "
    + "letter-spacing=\"\(spacing)\">\(escape(string))\(trailing)</text>"
}

func span(_ string: String, fill: String, size: Double? = nil) -> String {
  let sized = size.map { " font-size=\"\($0)\"" } ?? ""
  return "<tspan fill=\"\(fill)\"\(sized)>\(escape(string))</tspan>"
}

func rect(
  x: Double, y: Double, w: Double, h: Double, r: Double = 0, fill: String, stroke: String? = nil
) -> String {
  let line = stroke.map { " stroke=\"\($0)\" stroke-width=\"1\"" } ?? ""
  return "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"\(h)\" rx=\"\(r)\" "
    + "fill=\"\(fill)\"\(line)/>"
}

/// A 24 x 24 line glyph (the mockup's sidebar icons), drawn `size` wide at (x, y).
func glyph(_ paths: String, x: Double, y: Double, size: Double, color: String) -> String {
  "<g transform=\"translate(\(x) \(y)) scale(\(size / 24))\" fill=\"none\" stroke=\"\(color)\" "
    + "stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\(paths)</g>"
}

enum Glyph {
  static let key = "<circle cx=\"8\" cy=\"15\" r=\"4\"/><path d=\"M10.8 12.2 20 3M16 7l3 3M14 9l2 2\"/>"
  static let star = "<path d=\"M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z\"/>"
  static let person = "<circle cx=\"12\" cy=\"8\" r=\"4\"/><path d=\"M4 21c0-4 3.6-7 8-7s8 3 8 7\"/>"
  static let bank = "<path d=\"M3 10h18M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 21h18M12 3l9 5H3z\"/>"
  static let wifi =
    "<path d=\"M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0\"/>"
    + "<circle cx=\"12\" cy=\"19.5\" r=\"1\"/>"
  static let server =
    "<rect x=\"3\" y=\"4\" width=\"18\" height=\"7\" rx=\"1.5\"/>"
    + "<rect x=\"3\" y=\"13\" width=\"18\" height=\"7\" rx=\"1.5\"/><path d=\"M7 7.5h.01M7 16.5h.01\"/>"
  static let note = "<path d=\"M6 3h9l4 4v14H6z\"/><path d=\"M15 3v4h4M9 12h7M9 16h5\"/>"
  static let trash = "<path d=\"M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13\"/>"
  static let health =
    "<path d=\"M20.8 8.6a5 5 0 0 0-8.8-3.2 5 5 0 0 0-8.8 3.2c0 5.4 8.8 11.4 8.8 11.4s8.8-6 8.8-11.4z\"/>"
    + "<path d=\"M5 12h3l2-3 3 6 2-3h4\"/>"
  static let copy =
    "<rect x=\"8\" y=\"8\" width=\"13\" height=\"13\" rx=\"2\"/>"
    + "<path d=\"M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3\"/>"
}

/// The app icon (the same geometry as `scripts/make_icon.swift`), `size` wide at (x, y).
func icon(_ t: Theme, x: Double, y: Double, size: Double) -> String {
  // make_icon draws in a 1024 space with y up; the tile is the 824 square at 100.
  let s = size / 824
  return """
    <g transform="translate(\(x) \(y)) scale(\(s)) translate(-100 -100)">
      <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#iconTile)" filter="url(#soft)"/>
      <path d="M398 484 V394 A114 114 0 0 1 626 394 V484" fill="none" stroke="#FFFFFF" stroke-width="76" stroke-linecap="round"/>
      <rect x="300" y="454" width="424" height="330" rx="64" fill="#FFFFFF"/>
      <circle cx="512" cy="594" r="52" fill="\(t.iconBottom)"/>
      <path d="M482 614 H542 L556 704 H468 Z" fill="\(t.iconBottom)"/>
    </g>
    """
}

func tile(_ t: Theme, letter: String, family: String, x: Double, y: Double, size: Double)
  -> String
{
  let color = t.familyColor(family)
  return rect(x: x, y: y, w: size, h: size, r: size * 0.26, fill: t.tint(color, t.tileAlpha))
    + text(
      letter, x: x + size / 2, y: y + size * 0.67, size: size * 0.46, fill: color, weight: 600,
      anchor: "middle")
}

// MARK: - The banner

let width = 1200.0
let height = 560.0

func banner(_ t: Theme) -> String {
  var out: [String] = []
  out.append(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" "
      + "viewBox=\"0 0 \(width) \(height)\" role=\"img\" aria-label=\"PassFort: the app icon "
      + "and the vault window\">")
  out.append(
    """
    <defs>
      <linearGradient id="iconTile" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="\(t.iconTop)"/><stop offset="1" stop-color="\(t.iconBottom)"/>
      </linearGradient>
      <filter id="soft" x="-20%" y="-20%" width="140%" height="150%">
        <feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000" flood-opacity="0.28"/>
      </filter>
      <filter id="window" x="-10%" y="-10%" width="120%" height="125%">
        <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#000" flood-opacity="\(t.dark ? 0.5 : 0.16)"/>
      </filter>
      <clipPath id="windowClip"><rect x="470" y="48" width="690" height="464" rx="12"/></clipPath>
    </defs>
    """)
  out.append(rect(x: 0.5, y: 0.5, w: width - 1, h: height - 1, r: 24, fill: t.page, stroke: t.pageBorder))

  // Left: icon, name, tagline, three facts.
  out.append(icon(t, x: 64, y: 118, size: 112))
  out.append(text("PassFort", x: 60, y: 302, size: 54, fill: t.text, weight: 700, spacing: -1))
  out.append(text("A macOS password manager.", x: 62, y: 344, size: 20, fill: t.text2))
  out.append(text("Every key stays in a tiny C++ core.", x: 62, y: 372, size: 20, fill: t.text2))
  var chipX = 62.0
  for (label, w) in [("Argon2id", 88.0), ("XChaCha20-Poly1305", 170.0), ("Local-first", 104.0)] {
    out.append(rect(x: chipX, y: 404, w: w, h: 28, r: 14, fill: t.tint(t.brand, t.dark ? 0.2 : 0.12)))
    out.append(
      text(label, x: chipX + w / 2, y: 423, size: 13, fill: t.brand, weight: 600, anchor: "middle"))
    chipX += w + 8
  }

  // Right: the vault window.
  let wx = 470.0, wy = 48.0, ww = 690.0, wh = 464.0
  out.append(rect(x: wx, y: wy, w: ww, h: wh, r: 12, fill: t.list).replacingOccurrences(
    of: "/>", with: " filter=\"url(#window)\"/>"))
  out.append("<g clip-path=\"url(#windowClip)\">")

  // Sidebar.
  let sw = 172.0
  out.append(rect(x: wx, y: wy, w: sw, h: wh, fill: t.sidebar))
  for (i, c) in ["#FF5F57", "#FEBC2E", "#28C840"].enumerated() {
    out.append("<circle cx=\"\(wx + 18 + Double(i) * 18)\" cy=\"\(wy + 20)\" r=\"6\" fill=\"\(c)\"/>")
  }
  var sy = wy + 48
  func sideRow(_ glyphPaths: String, _ color: String, _ label: String, _ count: String?, selected: Bool = false) {
    if selected { out.append(rect(x: wx + 8, y: sy, w: sw - 16, h: 24, r: 6, fill: t.sideSelection)) }
    out.append(glyph(glyphPaths, x: wx + 16, y: sy + 4, size: 16, color: color))
    out.append(text(label, x: wx + 40, y: sy + 16.5, size: 12.5, fill: t.text, weight: selected ? 500 : 400))
    if let count {
      out.append(text(count, x: wx + sw - 16, y: sy + 16.5, size: 11, fill: t.text2, anchor: "end"))
    }
    sy += 26
  }
  sideRow(Glyph.key, t.brand, "All Accounts", "42", selected: true)
  sideRow(Glyph.star, t.star, "Favorites", "6")
  sy += 8
  out.append(text("Categories", x: wx + 16, y: sy + 8, size: 10.5, fill: t.text2, weight: 600))
  sy += 16
  sideRow(Glyph.person, t.familyColor("personal"), "Logins", "27")
  sideRow(Glyph.bank, t.familyColor("money"), "Bank Accounts", "3")
  sideRow(Glyph.wifi, t.familyColor("network"), "Wi-Fi", "2")
  sideRow(Glyph.server, t.familyColor("tech"), "Servers", "3")
  sideRow(Glyph.note, t.familyColor("notes"), "Secure Notes", "2")
  sy += 12
  sideRow(Glyph.health, t.danger, "Password Health", nil)
  out.append(rect(x: wx + sw - 34, y: sy - 22, w: 20, h: 16, r: 8, fill: t.danger))
  out.append(text("3", x: wx + sw - 24, y: sy - 10, size: 10.5, fill: "#FFFFFF", weight: 700, anchor: "middle"))
  sideRow(Glyph.trash, t.text2, "Recently Deleted", "2")
  out.append("<line x1=\"\(wx + sw)\" y1=\"\(wy)\" x2=\"\(wx + sw)\" y2=\"\(wy + wh)\" stroke=\"\(t.border)\"/>")

  // Account list.
  let lx = wx + sw, lw = 250.0
  out.append(text("All Accounts", x: lx + 14, y: wy + 28, size: 14, fill: t.text, weight: 600))
  out.append(rect(x: lx + 128, y: wy + 12, w: 108, h: 24, r: 6, fill: t.field))
  out.append(text("Search", x: lx + 140, y: wy + 28, size: 12, fill: t.text2))
  out.append("<line x1=\"\(lx)\" y1=\"\(wy + 46)\" x2=\"\(lx + lw)\" y2=\"\(wy + 46)\" stroke=\"\(t.border)\"/>")
  let accounts: [(String, String, String, Bool)] = [
    ("GitHub", "me@example.com", "personal", true),
    ("Current account", "•••• 3812", "money", true),
    ("Home Wi-Fi", "PassFort-5G", "network", false),
    ("NAS admin", "nas.local", "tech", false),
    ("Postgres (prod)", "db.internal", "tech", false),
    ("Recovery plan", "Secure note", "notes", false),
    ("Visa Debit", "•••• 4421", "money", false),
  ]
  var ry = wy + 54
  for (index, (title, sub, family, favorite)) in accounts.enumerated() {
    let selected = index == 0
    if selected {
      out.append(rect(x: lx + 8, y: ry, w: lw - 16, h: 46, r: 7, fill: t.selection))
      out.append(rect(x: lx + 16, y: ry + 8, w: 30, h: 30, r: 8, fill: "rgba(255,255,255,0.22)"))
      out.append(text("G", x: lx + 31, y: ry + 28, size: 14, fill: "#FFFFFF", weight: 600, anchor: "middle"))
    } else {
      out.append(tile(t, letter: String(title.prefix(1)), family: family, x: lx + 16, y: ry + 8, size: 30))
    }
    let titleColor = selected ? "#FFFFFF" : t.text
    let star = favorite ? span("  ★", fill: selected ? "#FFFFFF" : t.star, size: 11) : ""
    out.append(
      text(title, x: lx + 56, y: ry + 20, size: 13, fill: titleColor, weight: 500, trailing: star))
    out.append(
      text(sub, x: lx + 56, y: ry + 36, size: 11.5, fill: selected ? "rgba(255,255,255,0.85)" : t.text2))
    ry += 48
  }
  out.append("<line x1=\"\(lx + lw)\" y1=\"\(wy)\" x2=\"\(lx + lw)\" y2=\"\(wy + wh)\" stroke=\"\(t.border)\"/>")

  // Detail.
  let dx = lx + lw, dw = ww - sw - lw
  out.append(rect(x: dx, y: wy, w: dw, h: wh, fill: t.detail))
  out.append(tile(t, letter: "G", family: "personal", x: dx + 22, y: wy + 30, size: 46))
  out.append(text("GitHub", x: dx + 80, y: wy + 50, size: 19, fill: t.text, weight: 600))
  out.append(
    text(
      "github.com · ", x: dx + 80, y: wy + 70, size: 12, fill: t.text2,
      trailing: span("Login", fill: t.familyColor("personal"))))

  let cx = dx + 18, cw = dw - 36, cy = wy + 100
  out.append(rect(x: cx, y: cy, w: cw, h: 132, r: 10, fill: t.card, stroke: t.cardBorder))
  for i in 1...2 {
    let ly = cy + Double(i) * 44
    out.append("<line x1=\"\(cx)\" y1=\"\(ly)\" x2=\"\(cx + cw)\" y2=\"\(ly)\" stroke=\"\(t.border)\"/>")
  }
  out.append(text("Username", x: cx + 12, y: cy + 26, size: 11.5, fill: t.text2))
  out.append(text("me@example.com", x: cx + 92, y: cy + 26, size: 12, fill: t.text))
  out.append(glyph(Glyph.copy, x: cx + cw - 24, y: cy + 15, size: 13, color: t.text2))

  out.append(text("Password", x: cx + 12, y: cy + 70, size: 11.5, fill: t.text2))
  out.append(text("••••••••", x: cx + 92, y: cy + 70, size: 12, fill: t.text, family: mono))
  out.append(rect(x: cx + 158, y: cy + 58, w: 50, h: 17, r: 8.5, fill: t.tint(t.success, t.dark ? 0.18 : 0.14)))
  out.append(text("Strong", x: cx + 183, y: cy + 70.5, size: 10, fill: t.success, weight: 700, anchor: "middle"))

  out.append(text("Code", x: cx + 12, y: cy + 114, size: 11.5, fill: t.text2))
  out.append(text("482 913", x: cx + 92, y: cy + 115, size: 14, fill: t.text, weight: 500, family: mono))
  let ringX = cx + 170, ringY = cy + 110
  out.append(
    "<circle cx=\"\(ringX)\" cy=\"\(ringY)\" r=\"7\" fill=\"none\" stroke=\"\(t.ringTrack)\" stroke-width=\"2.5\"/>")
  out.append(
    "<circle cx=\"\(ringX)\" cy=\"\(ringY)\" r=\"7\" fill=\"none\" stroke=\"\(t.brand)\" stroke-width=\"2.5\" "
      + "stroke-linecap=\"round\" stroke-dasharray=\"26.4 44\" transform=\"rotate(-90 \(ringX) \(ringY))\"/>")
  out.append(text("18 s", x: ringX + 12, y: cy + 114, size: 11, fill: t.text2))

  let ny = cy + 148
  out.append(rect(x: cx, y: ny, w: cw, h: 84, r: 10, fill: t.card, stroke: t.cardBorder))
  out.append(text("Notes", x: cx + 12, y: ny + 22, size: 11, fill: t.text2))
  out.append(text("Personal account. Recovery", x: cx + 12, y: ny + 44, size: 12, fill: t.text))
  out.append(text("codes are in their section.", x: cx + 12, y: ny + 62, size: 12, fill: t.text))

  // The copy toast, at the foot of the list.
  let toastW = 200.0, toastX = lx + (lw - toastW) / 2, toastY = wy + wh - 44
  out.append(rect(x: toastX, y: toastY, w: toastW, h: 28, r: 14, fill: t.tint(t.success, t.dark ? 0.18 : 0.12)))
  out.append(
    "<g transform=\"translate(\(toastX + 12) \(toastY + 7)) scale(0.58)\" fill=\"none\" stroke=\"\(t.success)\" "
      + "stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">"
      + "<circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"m8 12 3 3 5-6\"/></g>")
  out.append(text("Password copied", x: toastX + 34, y: toastY + 18.5, size: 12, fill: t.success, weight: 500))

  out.append("</g>")
  out.append(rect(x: wx, y: wy, w: ww, h: wh, r: 12, fill: "none", stroke: t.frame))
  out.append("</svg>")
  return out.joined(separator: "\n") + "\n"
}

// MARK: - Main

let script = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let root = script.deletingLastPathComponent().deletingLastPathComponent()
let tokens: Tokens
do {
  tokens = try JSONDecoder().decode(
    Tokens.self, from: Data(contentsOf: root.appending(path: "UI/tokens.json")))
} catch {
  fail("can't read UI/tokens.json: \(error)")
}

let outDir = root.appending(path: "docs/images")
do {
  try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
  for (name, dark) in [("hero-light.svg", false), ("hero-dark.svg", true)] {
    try Data(banner(Theme(tokens, dark: dark)).utf8).write(
      to: outDir.appending(path: name), options: .atomic)
    print("wrote docs/images/\(name)")
  }
} catch {
  fail("can't write docs/images: \(error)")
}
