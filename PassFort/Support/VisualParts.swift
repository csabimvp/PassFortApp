import PassFortVault
import SwiftUI

// The small pieces of the visual language in the design mockups, shared by every screen that shows
// them: the category tile, the strength pill and meter, the one-time-code ring, the toast, and
// the classed rendering of a revealed password. Colours come from `Palette` only.

// MARK: - Icon button

/// A borderless icon button in the secondary colour — copy, reveal — so the actions on a row stay
/// quiet and orange is left to what carries meaning. White on a selected row, like its text. The
/// title is the tooltip and the accessibility label.
struct IconButton: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  init(_ title: String, systemImage: String, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.action = action
  }

  var body: some View {
    Button(title, systemImage: systemImage, action: action)
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .help(title)
  }
}

// MARK: - Category tile

/// A rounded square in the category family's faint tint, with the account's initial (or the
/// category's symbol, for a title with no letter) in the family colour. On a selected row of a
/// focused list it turns white on the selection colour, as the mockup's selected row does.
struct CategoryTile: View {
  let title: String
  let category: AccountCategory
  var size: CGFloat = 30

  @Environment(\.backgroundProminence) private var prominence

  var body: some View {
    let selected = prominence == .increased
    let family = category.family
    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
      .fill(selected ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(Palette.tint(family)))
      .frame(width: size, height: size)
      .overlay {
        Group {
          if let initial = Self.initial(of: title) {
            Text(initial).font(.system(size: size * 0.46, weight: .semibold))
          } else {
            Image(systemName: category.symbol).font(.system(size: size * 0.42, weight: .medium))
          }
        }
        .foregroundStyle(selected ? Color.white : Palette.color(family))
      }
      .accessibilityHidden(true)
  }

  /// The first letter or digit of `title`, uppercased; `nil` when there is none.
  static func initial(of title: String) -> String? {
    title.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() }
  }
}

// MARK: - Strength

/// A password's strength in the words and colours the UI uses, from `PasswordStrength`'s 0-4
/// score. Password Health reports weak and fair alike (both are below `PasswordAudit.weakBelow`);
/// the pill tells them apart so the worst read red and the borderline amber.
enum StrengthLevel: Equatable {
  case weak, fair, strong, veryStrong

  init(score: Int) {
    switch score {
    case ..<2: self = .weak
    case 2: self = .fair
    case 3: self = .strong
    default: self = .veryStrong
    }
  }

  init(password: String) {
    self.init(score: PasswordStrength.estimate(password).score)
  }

  var title: String {
    switch self {
    case .weak: "Weak"
    case .fair: "Fair"
    case .strong: "Strong"
    case .veryStrong: "Very strong"
    }
  }

  var color: Color {
    switch self {
    case .weak: Palette.danger
    case .fair: Palette.warning
    case .strong, .veryStrong: Palette.success
    }
  }

  /// Filled segments of the four-segment meter.
  var bars: Int {
    switch self {
    case .weak: 1
    case .fair: 2
    case .strong: 3
    case .veryStrong: 4
    }
  }
}

/// A capsule of tinted text — a strength pill, a status chip.
struct Pill: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(color.opacity(0.14), in: Capsule())
  }
}

/// The four-segment strength meter — the generator's, and the account form's under the password —
/// filled to `level` in its colour.
struct StrengthMeter: View {
  let level: StrengthLevel
  var height: CGFloat = 5

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<4, id: \.self) { index in
        Capsule()
          .fill(index < level.bars ? AnyShapeStyle(level.color) : AnyShapeStyle(.quaternary))
          .frame(height: height)
      }
    }
    .accessibilityElement()
    .accessibilityLabel("Strength: \(level.title)")
  }
}

// MARK: - One-time code ring

/// How much of the code's period is left, as a ring in the brand colour that turns `danger` for
/// the last five seconds.
struct CountdownRing: View {
  let remaining: Int
  let period: Int

  var body: some View {
    let urgent = remaining <= 5
    ZStack {
      Circle().stroke(.quaternary, lineWidth: 2.5)
      Circle()
        .trim(from: 0, to: Double(remaining) / Double(max(period, 1)))
        .stroke(
          urgent ? Palette.danger : Palette.primary,
          style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
    }
    .frame(width: 15, height: 15)
    .accessibilityElement()
    .accessibilityLabel("\(remaining) seconds left")
  }
}

// MARK: - Toast

/// A transient confirmation ("Password copied") as a tinted capsule.
struct Toast: View {
  let text: String
  var systemImage = "checkmark.circle"
  var color = Palette.success
  /// A button at the end, e.g. Undo.
  var actionTitle: String?
  var onAction: () -> Void = {}

  var body: some View {
    HStack(spacing: 10) {
      Label(text, systemImage: systemImage)
        .foregroundStyle(color)
        .lineLimit(1)
      if let actionTitle {
        Button(actionTitle, action: onAction)
          .buttonStyle(.borderless)
          .foregroundStyle(Palette.primary)
          .fontWeight(.semibold)
      }
    }
    .font(.caption.weight(.medium))
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    .background(color.opacity(0.14), in: Capsule())
    .accessibilityAddTraits(.updatesFrequently)
  }
}

// MARK: - Revealed password

/// A password with its digits in the personal-family blue and its symbols in the brand colour,
/// so `0`/`O` and `l`/`1` read apart. Letters keep the surrounding text colour.
enum ClassedPassword {
  enum CharacterClass: Equatable {
    case letter, digit, symbol
  }

  static func characterClass(of character: Character) -> CharacterClass {
    if character.isNumber { return .digit }
    if character.isLetter { return .letter }
    return .symbol
  }

  static func text(_ password: String) -> Text {
    var styled = AttributedString()
    for character in password {
      var run = AttributedString(String(character))
      switch characterClass(of: character) {
      case .digit: run.foregroundColor = Palette.color(.personal)
      case .symbol: run.foregroundColor = Palette.primary
      case .letter: break
      }
      styled += run
    }
    return Text(styled)
  }
}
