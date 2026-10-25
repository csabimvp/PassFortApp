import SwiftUI

/// A secret shown as dots until revealed, with a copy that clears itself (`CopyButton`) and no
/// text selection, so the only way out is the self-clearing copy. Every secret in the detail view
/// goes through this, so none of them is on screen by default. The reveal is per row and dies
/// with the row — the owning view gives the rows a fresh identity per account, so switching
/// accounts re-conceals everything. A revealed value shows its digits and symbols in colour
/// (`ClassedPassword`); `showsStrength` adds a strength pill, for the account's password.
struct ConcealedRow: View {
  let label: String
  let value: String
  var showsStrength = false

  @State private var revealed = false

  var body: some View {
    LabeledContent(label) {
      HStack {
        Group {
          if revealed {
            ClassedPassword.text(value)
          } else {
            Text(String(repeating: "•", count: 12))
          }
        }
        .font(.system(.body, design: .monospaced))
        if showsStrength {
          let level = StrengthLevel(password: value)
          Pill(text: level.title, color: level.color)
        }
        Spacer()
        IconButton(
          revealed ? "Hide \(label.lowercased())" : "Reveal \(label.lowercased())",
          systemImage: revealed ? "eye.slash" : "eye"
        ) { revealed.toggle() }
        CopyButton(label: label, value: value, kind: .secret)
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
