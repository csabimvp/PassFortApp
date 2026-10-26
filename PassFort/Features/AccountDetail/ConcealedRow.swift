import SwiftUI

/// A secret shown as dots until revealed, with a copy that clears itself (`CopyButton`) and no
/// text selection, so the only way out is the self-clearing copy. Every secret in the detail view
/// goes through this, so none of them is on screen by default. The reveal is per row and dies
/// with the row — the owning view gives the rows a fresh identity per account, so switching
/// accounts re-conceals everything. A revealed value shows its digits and symbols in colour
/// (`ClassedPassword`); `showsStrength` adds a "Strength" row (meter and pill) beneath, for the
/// account's password — so the view is one or two rows of the enclosing form.
struct ConcealedRow: View {
  let label: String
  let value: String
  var showsStrength = false

  @State private var revealed = false

  var body: some View {
    LabeledContent(label) {
      // No Spacer: the value and its buttons sit together at the trailing edge, so the buttons
      // stay put whether the row shows dots or the revealed text.
      HStack(spacing: 6) {
        Group {
          if revealed {
            ClassedPassword.text(value)
          } else {
            Text(String(repeating: "•", count: 12))
          }
        }
        .font(.system(.body, design: .monospaced))
        IconButton(
          revealed ? "Hide \(label.lowercased())" : "Reveal \(label.lowercased())",
          systemImage: revealed ? "eye.slash" : "eye"
        ) { revealed.toggle() }
        CopyButton(label: label, value: value, kind: .secret)
      }
    }
    if showsStrength {
      let level = StrengthLevel(password: value)
      LabeledContent("Strength") {
        HStack(spacing: 8) {
          StrengthMeter(level: level, height: 4).frame(width: 56)
          Pill(text: level.title, color: level.color)
        }
      }
    }
  }
}

#Preview {
  Form {
    ConcealedRow(label: "Password", value: "hunter2", showsStrength: true)
    ConcealedRow(label: "PIN", value: "4821")
  }
  .formStyle(.grouped)
}
