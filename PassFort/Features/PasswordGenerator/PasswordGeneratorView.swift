import PassFortVault
import SwiftUI

/// What the generator makes: random characters or a passphrase. The generator mockup's
/// Characters | Words switch.
enum GeneratorKind: String, CaseIterable {
  case characters, words

  var title: String {
    switch self {
    case .characters: "Characters"
    case .words: "Words"
    }
  }
}

/// One generation request — the policy for the selected kind — so the view regenerates on any
/// change with a single `onChange`, and the choices are testable without the view.
enum GeneratorRequest: Equatable {
  case characters(PasswordPolicy)
  case words(PassphrasePolicy)

  static let lengthRange = 8...64
  static let wordRange = 3...10

  /// The Characters policy from the generator's options. Lowercase is always on, as in the
  /// mockup, so no combination of checkboxes leaves an empty alphabet; each enabled class is
  /// guaranteed at least one character.
  static func characters(
    length: Int, uppercase: Bool, digits: Bool, symbols: Bool, excludeAmbiguous: Bool
  ) -> GeneratorRequest {
    .characters(
      PasswordPolicy(
        length: length.clamped(to: lengthRange),
        lowercase: true, uppercase: uppercase, digits: digits, symbols: symbols,
        excludeAmbiguous: excludeAmbiguous,
        minLowercase: 1, minUppercase: uppercase ? 1 : 0,
        minDigits: digits ? 1 : 0, minSymbols: symbols ? 1 : 0))
  }

  static func words(count: Int, separator: String, capitalize: Bool, digit: Bool)
    -> GeneratorRequest
  {
    .words(
      PassphrasePolicy(
        wordCount: count.clamped(to: wordRange), separator: separator,
        capitalize: capitalize, includeDigit: digit))
  }

  /// A fresh value, or `""` if the policy can't produce one (it always can, from the options
  /// above).
  func generate() -> String {
    switch self {
    case .characters(let policy): (try? policy.generate()) ?? ""
    case .words(let policy): (try? policy.generate()) ?? ""
    }
  }

  var entropyBits: Double? {
    switch self {
    case .characters(let policy): try? policy.entropyBits()
    case .words(let policy): try? policy.entropyBits()
    }
  }
}

/// The separators the Words mode offers, by name.
enum PassphraseSeparator: String, CaseIterable, Identifiable {
  case hyphen = "-"
  case period = "."
  case underscore = "_"
  case space = " "
  case none = ""

  var id: String { rawValue }

  var title: String {
    switch self {
    case .hyphen: "Hyphen  -"
    case .period: "Period  ."
    case .underscore: "Underscore  _"
    case .space: "Space"
    case .none: "None"
    }
  }
}

/// The password generator, laid out as the mockup's: a Characters | Words switch beside the
/// title, the value in a monospaced well with digits and symbols classed, the four-bar meter,
/// then the options for the selected kind. Options persist in `UserDefaults` (`@AppStorage`),
/// shared by every place the generator opens.
///
/// `onUse == nil` → standalone (Copy button, e.g. the toolbar). `onUse` set → "Use Password"
/// hands the value to the caller (the account form's popover).
struct PasswordGeneratorView: View {
  var onUse: ((String) -> Void)?

  @Environment(\.dismiss) private var dismiss

  @AppStorage("gen.kind") private var kind = GeneratorKind.characters
  @AppStorage("gen.length") private var length = 20
  @AppStorage("gen.uppercase") private var uppercase = true
  @AppStorage("gen.digits") private var digits = true
  @AppStorage("gen.symbols") private var symbols = true
  @AppStorage("gen.excludeAmbiguous") private var excludeAmbiguous = true
  @AppStorage("gen.words.count") private var wordCount = 5
  @AppStorage("gen.words.separator") private var separator = PassphraseSeparator.hyphen
  @AppStorage("gen.words.capitalize") private var capitalize = false
  @AppStorage("gen.words.digit") private var wordDigit = false

  @State private var generated = ""
  @State private var copied = false

  private var request: GeneratorRequest {
    switch kind {
    case .characters:
      .characters(
        length: length, uppercase: uppercase, digits: digits, symbols: symbols,
        excludeAmbiguous: excludeAmbiguous)
    case .words:
      .words(
        count: wordCount, separator: separator.rawValue, capitalize: capitalize,
        digit: wordDigit)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Generate Password").font(.headline)
        Spacer()
        Picker("Kind", selection: $kind) {
          ForEach(GeneratorKind.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
      }

      valueWell
      strength

      switch kind {
      case .characters: characterOptions
      case .words: wordOptions
      }

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
      .padding(.top, 4)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 22)
    .frame(width: 420)
    .onAppear(perform: regenerate)
    .onChange(of: request) { regenerate() }
  }

  // MARK: - Value and strength

  private var valueWell: some View {
    HStack(spacing: 8) {
      ClassedPassword.text(generated.isEmpty ? " " : generated)
        .font(.system(size: 17, design: .monospaced))
        .tracking(0.5)
        .textSelection(.enabled)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
      IconButton("Generate another", systemImage: "arrow.clockwise", action: regenerate)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
  }

  @ViewBuilder
  private var strength: some View {
    let level = StrengthLevel(password: generated)
    VStack(alignment: .leading, spacing: 6) {
      StrengthMeter(level: level)
      HStack {
        Text(level.title).foregroundStyle(level.color).fontWeight(.semibold)
        Spacer()
        Text(entropyLabel).foregroundStyle(.secondary)
      }
      .font(.caption)
    }
    .opacity(generated.isEmpty ? 0 : 1)
  }

  private var entropyLabel: String {
    guard let bits = request.entropyBits else { return "" }
    return "about \(Int(bits.rounded())) bits"
  }

  // MARK: - Options

  private var characterOptions: some View {
    VStack(alignment: .leading, spacing: 12) {
      labeledSlider("Length", value: $length, in: GeneratorRequest.lengthRange)
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
        GridRow {
          Toggle("Uppercase  A–Z", isOn: $uppercase)
          Toggle(isOn: $digits) {
            Text("Digits  \(Text("0–9").foregroundStyle(Palette.color(.personal)))")
          }
        }
        GridRow {
          Toggle(isOn: $symbols) {
            Text("Symbols  \(Text("!@#$").foregroundStyle(Palette.primary))")
          }
          Toggle("No look-alikes", isOn: $excludeAmbiguous)
            .help("Leave out 0 O 1 l I")
        }
      }
      .toggleStyle(.checkbox)
    }
  }

  private var wordOptions: some View {
    VStack(alignment: .leading, spacing: 12) {
      labeledSlider("Words", value: $wordCount, in: GeneratorRequest.wordRange)
      HStack(spacing: 12) {
        Text("Separator").frame(width: 70, alignment: .leading)
        Picker("Separator", selection: $separator) {
          ForEach(PassphraseSeparator.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
      }
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
        GridRow {
          Toggle("Capitalize", isOn: $capitalize)
          Toggle(isOn: $wordDigit) {
            Text("Add a digit  \(Text("0–9").foregroundStyle(Palette.color(.personal)))")
          }
        }
      }
      .toggleStyle(.checkbox)
    }
  }

  /// A labelled slider with its value on the right, as the mockup's Length row.
  private func labeledSlider(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>)
    -> some View
  {
    HStack(spacing: 12) {
      Text(title).frame(width: 70, alignment: .leading)
      // No `step`: on a wide range it would draw a tick mark per value.
      Slider(
        value: Binding(
          get: { Double(value.wrappedValue.clamped(to: range)) },
          set: { value.wrappedValue = Int($0.rounded()) }),
        in: Double(range.lowerBound)...Double(range.upperBound))
      Text("\(value.wrappedValue.clamped(to: range))")
        .monospacedDigit()
        .frame(width: 24, alignment: .trailing)
    }
  }

  private func regenerate() {
    copied = false
    generated = request.generate()
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

#Preview("Standalone") {
  PasswordGeneratorView()
}

#Preview("In the account form") {
  PasswordGeneratorView { _ in }
}
