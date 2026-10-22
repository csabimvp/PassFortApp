import SwiftUI

/// A secret shown as dots until revealed, with a copy that clears itself (`copyTransient`) and no
/// text selection, so the only way out is the self-clearing copy. Every secret in the detail view
/// goes through this, so none of them is on screen by default. The reveal is per row and dies
/// with the row — the owning view gives the rows a fresh identity per account, so switching
/// accounts re-conceals everything.
struct ConcealedRow: View {
  let label: String
  let value: String

  @State private var revealed = false

  var body: some View {
    LabeledContent(label) {
      HStack {
        Text(revealed ? value : String(repeating: "•", count: 12))
          .font(.system(.body, design: .monospaced))
        Spacer()
        Button(revealed ? "Hide" : "Reveal") { revealed.toggle() }
        Button("Copy") { Pasteboard.copyTransient(value) }
      }
    }
  }
}

#Preview {
  Form {
    ConcealedRow(label: "Password", value: "hunter2")
  }
  .formStyle(.grouped)
}
