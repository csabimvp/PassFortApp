import PassFortVault
import SwiftUI

/// A password generator with the same knobs as `passfort-cli gen` — length and
/// the four character classes, plus the exclude-look-alikes toggle. Preferences
/// persist in `UserDefaults` (`@AppStorage`), shared with the account form.
///
/// `onUse == nil` → standalone (Copy button, e.g. the Tools menu). `onUse` set →
/// "Use Password" hands the value to the caller (the account form).
struct PasswordGeneratorView: View {
  var onUse: ((String) -> Void)?

  @Environment(\.dismiss) private var dismiss

  @AppStorage("gen.length") private var length = 20
  @AppStorage("gen.lowercase") private var lowercase = true
  @AppStorage("gen.uppercase") private var uppercase = true
  @AppStorage("gen.digits") private var digits = true
  @AppStorage("gen.symbols") private var symbols = true
  @AppStorage("gen.excludeAmbiguous") private var excludeAmbiguous = true

  @State private var generated = ""
  @State private var copied = false

  private var enabledClasses: Int {
    [lowercase, uppercase, digits, symbols].filter { $0 }.count
  }

  private var policy: PasswordPolicy {
    PasswordPolicy(
      length: length,
      lowercase: lowercase, uppercase: uppercase, digits: digits, symbols: symbols,
      excludeAmbiguous: excludeAmbiguous,
      minLowercase: lowercase ? 1 : 0, minUppercase: uppercase ? 1 : 0,
      minDigits: digits ? 1 : 0, minSymbols: symbols ? 1 : 0)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Generate Password").font(.headline)

      HStack(spacing: 8) {
        Text(generated.isEmpty ? " " : generated)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button("Generate another", systemImage: "arrow.clockwise", action: regenerate)
          .labelStyle(.iconOnly)
      }
      .padding(10)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

      if !generated.isEmpty {
        Text(entropyLabel).font(.caption).foregroundStyle(.secondary)
      }

      Stepper("Length: \(length)", value: $length, in: 8...128)

      Toggle("Lowercase  a–z", isOn: $lowercase).disabled(isOnlyClass(lowercase))
      Toggle("Uppercase  A–Z", isOn: $uppercase).disabled(isOnlyClass(uppercase))
      Toggle("Digits  0–9", isOn: $digits).disabled(isOnlyClass(digits))
      Toggle("Symbols  !@#$…", isOn: $symbols).disabled(isOnlyClass(symbols))
      Toggle("Exclude look-alikes  0 O 1 l I", isOn: $excludeAmbiguous)

      Divider()
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        if let onUse {
          Button("Use Password") {
            onUse(generated)
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(generated.isEmpty)
        } else {
          Button(copied ? "Copied" : "Copy") {
            Pasteboard.copyTransient(generated)
            copied = true
          }
          .keyboardShortcut(.defaultAction)
          .disabled(generated.isEmpty)
        }
      }
    }
    .padding(20)
    .frame(width: 380)
    .onAppear(perform: regenerate)
    .onChange(of: policy) { regenerate() }
  }

  private var entropyLabel: String {
    guard let bits = try? policy.entropyBits() else { return "" }
    return "~\(Int(bits.rounded())) bits of entropy"
  }

  /// True when `thisOne` is the last character class still on — so its toggle is
  /// disabled and the policy can never end up with zero classes.
  private func isOnlyClass(_ thisOne: Bool) -> Bool {
    thisOne && enabledClasses == 1
  }

  private func regenerate() {
    copied = false
    generated = (try? policy.generate()) ?? ""
  }
}

#Preview {
  PasswordGeneratorView()
}
