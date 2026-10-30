import Foundation
import PassFortVault

#if canImport(Glibc)
  import Glibc
#endif

// MARK: - Style

/// ANSI styling for a person at a terminal, and none for a pipe, a file, `NO_COLOR`
/// (no-color.org) or `TERM=dumb` -- so a script reads the same plain text either way.
struct Style: Sendable {
  let enabled: Bool

  static let plain = Style(enabled: false)

  /// For what is printed to stdout.
  static var stdout: Style {
    let environment = ProcessInfo.processInfo.environment
    let noColor = !(environment["NO_COLOR"] ?? "").isEmpty
    return Style(
      enabled: isatty(STDOUT_FILENO) == 1 && !noColor && environment["TERM"] != "dumb")
  }

  func bold(_ text: String) -> String { apply("1", text) }
  func dim(_ text: String) -> String { apply("2", text) }
  func red(_ text: String) -> String { apply("31", text) }
  func green(_ text: String) -> String { apply("32", text) }
  func yellow(_ text: String) -> String { apply("33", text) }

  private func apply(_ code: String, _ text: String) -> String {
    enabled && !text.isEmpty ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
  }
}

/// `text` cut to `width` characters, ending in "…" when it was longer.
func truncated(_ text: String, to width: Int) -> String {
  text.count <= width ? text : String(text.prefix(max(width - 1, 0))) + "…"
}

private func padded(_ text: String, to width: Int) -> String {
  text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

// MARK: - list

/// `list`'s table: `rows` by title, each under its short id from `ids` (`shortIDs`). A column is
/// as wide as its widest value, up to a cap past which values are cut with "…".
func summaryTable(_ rows: [AccountSummary], ids: [UUID: String], style: Style) -> String {
  guard !rows.isEmpty else { return style.dim("(no matching accounts)") + "\n" }
  let sorted = rows.sorted {
    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
  }
  let caps = [36, 32, 24, 32]
  let header = ["ID", "TITLE", "USERNAME", "HOST"]
  let cells = sorted.map { row in
    zip([ids[row.id] ?? row.id.uuidString.lowercased(), row.title, row.username, row.host], caps)
      .map { value, cap in truncated(value ?? "-", to: cap) }
  }
  let widths = header.indices.map { column in
    ([header[column]] + cells.map { $0[column] }).map(\.count).max() ?? 0
  }

  var out =
    style.bold(
      header.indices.map { padded(header[$0], to: widths[$0]) }
        .joined(separator: "  ").trimmingCharacters(in: .whitespaces)) + "\n"
  for (row, values) in zip(sorted, cells) {
    var flags: [String] = []
    if row.favorite { flags.append(style.yellow("★")) }
    if row.isConflict { flags.append(style.yellow("conflict")) }
    if row.isDeleted { flags.append(style.red("deleted")) }
    // The last column is padded only when flags follow it, so no line ends in spaces.
    let last = values.count - 1
    let columns = values.indices.map { column in
      let text =
        column == last && flags.isEmpty
        ? values[column] : padded(values[column], to: widths[column])
      return values[column] == "-" || column == 0 || row.isDeleted ? style.dim(text) : text
    }
    out += (columns + flags).joined(separator: "  ") + "\n"
  }
  if style.enabled {
    out += style.dim("\(rows.count) account\(rows.count == 1 ? "" : "s")") + "\n"
  }
  return out
}

// MARK: - get

/// `get`'s view of one account: the title as a heading, then the login, the details and the
/// record's history, each a block of aligned rows. The password, PIN, memorable word and
/// recovery codes show only with `reveal`, so a plain `get` leaves no secret in the scrollback
/// (§3.4).
func accountCard(_ account: Account, reveal: Bool, style: Style, now: Date = .now) -> String {
  let payload = account.payload
  var hidden = false
  func secret(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    if reveal { return value }
    hidden = true
    return "••••••••"
  }
  let day = DateFormatter()
  day.locale = Locale(identifier: "en_US_POSIX")
  day.dateFormat = "yyyy-MM-dd HH:mm"

  var login: [(String, String?)] = [
    ("username", payload.username),
    ("password", secret(payload.password)),
    ("email", payload.email),
    (
      "urls",
      payload.urls.isEmpty ? nil : payload.urls.map(\.absoluteString).joined(separator: "\n")
    ),
  ]
  if let totp = payload.totp {
    let left = style.dim("(\(totp.secondsRemaining(at: now))s left)")
    login.append(("one-time code", "\(style.bold(totp.code(at: now))) \(left)"))
  }
  login += [
    ("pin", secret(payload.pin)),
    ("memorable", secret(payload.memorableWord)),
    ("recovery codes", secret(payload.recoveryCodes.joined(separator: ", "))),
    (
      "sec questions",
      payload.securityQuestions.isEmpty ? nil : "\(payload.securityQuestions.count)"
    ),
  ]

  let details: [(String, String?)] = [
    ("notes", payload.notes),
    ("category", payload.category.rawValue),
    ("tags", payload.tags.isEmpty ? nil : payload.tags.joined(separator: ", ")),
    ("expires", payload.expiresAt.map(day.string)),
  ]

  var history: [(String, String?)] = [
    ("id", account.id.uuidString),
    ("version", String(account.version)),
    ("created", day.string(from: payload.createdAt)),
    ("updated", day.string(from: account.lastUpdated)),
    ("pw changed", payload.passwordChangedAt.map(day.string)),
  ]
  if let latest = payload.revisionHistory.first {
    history.append(
      (
        "revisions",
        "\(payload.revisionHistory.count) (latest: \(latest.changed.joined(separator: ", ")))"
      ))
  }
  if !payload.passwordHistory.isEmpty {
    history.append(("old passwords", "\(payload.passwordHistory.count) -- `history --passwords`"))
  }

  let blocks = [login, details, history.map { ($0.0, $0.1.map(style.dim)) }]
    .map { $0.compactMap { label, value in value.flatMap { $0.isEmpty ? nil : (label, $0) } } }
    .filter { !$0.isEmpty }
  let width = (blocks.joined().map(\.0.count).max() ?? 0) + 2

  var heading = style.bold(payload.title)
  if payload.favorite { heading += " " + style.yellow("★") }
  if account.isDeleted { heading += "  " + style.red("deleted") }
  var out = heading + "\n"
  for block in blocks {
    out += "\n"
    for (label, value) in block {
      let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
      out +=
        "  " + style.dim(padded(label, to: width)) + (lines.first.map(String.init) ?? "") + "\n"
      for line in lines.dropFirst() {
        out += "  " + String(repeating: " ", count: width) + line + "\n"
      }
    }
  }
  if hidden {
    out += "\n" + style.dim("  secrets hidden -- `copy` the password, or pass --reveal") + "\n"
  }
  return out
}
