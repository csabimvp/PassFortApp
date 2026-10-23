#!/usr/bin/env swift
// Regenerates PassFort's app icon: every size in AppIcon.appiconset plus its Contents.json.
//
//   swift scripts/make_icon.swift PassFort/Assets.xcassets/AppIcon.appiconset
//
// Pure CoreGraphics/ImageIO, so there is nothing to install. Each size is drawn directly from the
// vector description below (not downscaled from the 1024 master), which keeps the 16 and 32 px
// versions crisp. The colours are read from the brand in `UI/tokens.json`, so the icon matches the
// app's accent: the tile runs from the dark-mode brand at the top to the light-mode brand at the
// bottom, and the keyhole is the light-mode brand. Retheme in the tokens, then re-run this.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Brand colours, from UI/tokens.json

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("make_icon: \(message)\n".utf8))
  exit(1)
}

/// `"#RRGGBB"` → an sRGB colour.
func color(_ hex: String) -> CGColor {
  guard hex.count == 7, hex.hasPrefix("#"), let rgb = Int(hex.dropFirst(), radix: 16) else {
    fail("\"\(hex)\" is not #RRGGBB")
  }
  return CGColor(
    srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
    blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
}

let script = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let tokensURL = script.deletingLastPathComponent().deletingLastPathComponent()
  .appending(path: "UI/tokens.json")
guard
  let data = try? Data(contentsOf: tokensURL),
  let tokens = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
  let brand = tokens["brand"] as? [String: String],
  let brandLight = brand["light"], let brandDark = brand["dark"]
else { fail("can't read brand.light / brand.dark from \(tokensURL.path)") }

// MARK: - Design (all in a 1024 x 1024 space, origin bottom-left)

let tileTop = color(brandDark)
let tileBottom = color(brandLight)
let glyph = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let keyhole = color(brandLight)

func draw(into ctx: CGContext, pixels: Int) {
  let s = CGFloat(pixels) / 1024
  ctx.scaleBy(x: s, y: s)

  // The macOS icon tile: an 824 pt rounded square centred in the 1024 canvas.
  let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
  let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

  // Soft drop shadow, skipped where it would only blur the 16 px icon into mud.
  if pixels >= 64 {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(tileBottom)
    ctx.fillPath()
    ctx.restoreGState()
  }

  ctx.saveGState()
  ctx.addPath(tilePath)
  ctx.clip()
  let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [tileTop, tileBottom] as CFArray,
    locations: [0, 1])!
  ctx.drawLinearGradient(
    gradient, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
  ctx.restoreGState()

  // Padlock: shackle, body, keyhole.
  ctx.saveGState()
  if pixels >= 64 {
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: CGColor(gray: 0, alpha: 0.25))
  }
  ctx.setStrokeColor(glyph)
  ctx.setLineWidth(76)
  ctx.setLineCap(.round)
  ctx.beginPath()
  ctx.move(to: CGPoint(x: 398, y: 540))
  ctx.addLine(to: CGPoint(x: 398, y: 630))
  ctx.addArc(center: CGPoint(x: 512, y: 630), radius: 114, startAngle: .pi, endAngle: 0, clockwise: true)
  ctx.addLine(to: CGPoint(x: 626, y: 540))
  ctx.strokePath()

  let body = CGRect(x: 300, y: 240, width: 424, height: 330)
  ctx.addPath(CGPath(roundedRect: body, cornerWidth: 64, cornerHeight: 64, transform: nil))
  ctx.setFillColor(glyph)
  ctx.fillPath()
  ctx.restoreGState()

  ctx.setFillColor(keyhole)
  ctx.fillEllipse(in: CGRect(x: 512 - 52, y: 430 - 52, width: 104, height: 104))
  ctx.beginPath()
  ctx.move(to: CGPoint(x: 512 - 30, y: 410))
  ctx.addLine(to: CGPoint(x: 512 + 30, y: 410))
  ctx.addLine(to: CGPoint(x: 512 + 44, y: 320))
  ctx.addLine(to: CGPoint(x: 512 - 44, y: 320))
  ctx.closePath()
  ctx.fillPath()
}

// MARK: - Output

func writePNG(pixels: Int, to url: URL) throws {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  guard
    let ctx = CGContext(
      data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw CocoaError(.fileWriteUnknown) }
  ctx.interpolationQuality = .high
  draw(into: ctx, pixels: pixels)
  CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
  guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: make_icon.swift <AppIcon.appiconset dir>\n".utf8))
  exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try writePNG(pixels: points * scale, to: outDir.appending(path: name))
    images.append([
      "filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)",
    ])
  }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
  .write(to: outDir.appending(path: "Contents.json"))
print("wrote \(images.count) icons to \(outDir.path)")
