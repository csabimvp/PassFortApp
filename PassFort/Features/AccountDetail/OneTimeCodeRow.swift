import PassFortVault
import SwiftUI

/// The live one-time code: recomputed every second (a `TimelineView`, so nothing runs while the row
/// is off screen), with the seconds left as a ring and a self-clearing copy. The code is shown, unlike the
/// password — it is useless half a minute later, and it is what the user came to read.
struct OneTimeCodeRow: View {
  let config: TOTPConfig

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let code = config.code(at: context.date)
      let remaining = config.secondsRemaining(at: context.date)
      LabeledContent("One-time code") {
        HStack {
          Text(Self.grouped(code))
            .font(.system(.body, design: .monospaced))
            .monospacedDigit()
          CountdownRing(remaining: remaining, period: config.period)
          Text("\(remaining) s")
            .font(.caption).monospacedDigit()
            .foregroundStyle(remaining <= 5 ? Palette.danger : Color.secondary)
            .accessibilityHidden(true)
          Spacer()
          IconButton("Copy one-time code", systemImage: "doc.on.doc") {
            Pasteboard.copyTransient(code)
          }
        }
      }
    }
  }

  /// "123456" → "123 456", "12345678" → "1234 5678" — easier to read off the screen.
  static func grouped(_ code: String) -> String {
    let middle = code.index(code.startIndex, offsetBy: code.count / 2)
    return String(code[..<middle]) + " " + String(code[middle...])
  }
}

#Preview {
  Form {
    OneTimeCodeRow(config: TOTPConfig(secret: Data("12345678901234567890".utf8)))
  }
  .formStyle(.grouped)
}
