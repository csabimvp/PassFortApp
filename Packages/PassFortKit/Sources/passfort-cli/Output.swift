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

/// A date as people read it: local time to the minute (or just the day), not ISO 8601.
func displayDate(_ date: Date, time: Bool = true) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = time ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
  return formatter.string(from: date)
}

/// Blocks of label / value rows, labels dim and aligned across every block, a blank line before
/// each block. A row with no value is left out, and so is a block left empty. A multi-line value
/// stays in the value column.
func fieldBlocks(_ blocks: [[(String, String?)]], style: Style) -> String {
  let present =
    blocks
    .map { $0.compactMap { label, value in value.flatMap { $0.isEmpty ? nil : (label, $0) } } }
    .filter { !$0.isEmpty }
  let width = (present.joined().map(\.0.count).max() ?? 0) + 2
  var out = ""
  for block in present {
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
  return out
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
    ("expires", payload.expiresAt.map { displayDate($0) }),
  ]

  var history: [(String, String?)] = [
    ("id", account.id.uuidString),
    ("version", String(account.version)),
    ("created", displayDate(payload.createdAt)),
    ("updated", displayDate(account.lastUpdated)),
    ("pw changed", payload.passwordChangedAt.map { displayDate($0) }),
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

  var heading = style.bold(payload.title)
  if payload.favorite { heading += " " + style.yellow("★") }
  if account.isDeleted { heading += "  " + style.red("deleted") }
  var out = heading + "\n"
  out += fieldBlocks([login, details, history.map { ($0.0, $0.1.map(style.dim)) }], style: style)
  if hidden {
    out += "\n" + style.dim("  secrets hidden -- `copy` the password, or pass --reveal") + "\n"
  }
  return out
}

// MARK: - history

/// `history`'s view: the account, its revisions newest first, then its old passwords -- hidden
/// unless `passwords`.
func historyView(_ account: Account, passwords: Bool, style: Style) -> String {
  let payload = account.payload
  var heading =
    style.bold(payload.title) + "  " + style.dim("\(account.id.uuidString), v\(account.version)")
  if account.isDeleted { heading += "  " + style.red("deleted") }
  var out = heading + "\n\n"

  if payload.revisionHistory.isEmpty {
    out += style.dim("  no recorded revisions") + "\n"
  } else {
    let width = payload.revisionHistory.map { "v\($0.version)".count }.max() ?? 0
    for entry in payload.revisionHistory {
      out += "  " + style.bold(padded("v\(entry.version)", to: width)) + "  "
      out += style.dim(displayDate(entry.at)) + "  " + entry.changed.joined(separator: ", ") + "\n"
    }
    if payload.revisionHistory.count >= VaultRepository.revisionHistoryLimit {
      let cap = VaultRepository.revisionHistoryLimit
      out += style.dim("  (older revisions dropped -- the last \(cap) are kept)") + "\n"
    }
  }

  guard !payload.passwordHistory.isEmpty else { return out }
  out +=
    "\n" + style.bold("Previous passwords") + " " + style.dim("(\(payload.passwordHistory.count))")
    + "\n"
  for old in payload.passwordHistory {
    out += "  " + style.dim(displayDate(old.replacedAt)) + "  "
    out += (passwords ? old.password : "••••••••") + "\n"
  }
  if !passwords {
    out += "\n" + style.dim("  old passwords hidden -- pass --passwords") + "\n"
  }
  return out
}

// MARK: - audit

/// `audit`'s table: each finding with its account, the serious ones (weak, reused, expired) in
/// red and the rest in yellow.
func auditTable(_ findings: [AuditFinding], titles: [UUID: String], style: Style) -> String {
  guard !findings.isEmpty else {
    return style.green("no findings -- nothing weak, reused, old, expiring or on http://") + "\n"
  }
  let described = findings.map { finding in
    (describe(finding.kind), titles[finding.account] ?? finding.account.uuidString, finding.kind)
  }
  let width = max(described.map(\.0.count).max() ?? 0, "FINDING".count)
  var out = style.bold(padded("FINDING", to: width) + "  ACCOUNT") + "\n"
  for (text, title, kind) in described {
    let cell = padded(text, to: width)
    out += (isSerious(kind) ? style.red(cell) : style.yellow(cell)) + "  " + title + "\n"
  }
  return out + style.dim("\(findings.count) finding\(findings.count == 1 ? "" : "s")") + "\n"
}

private func isSerious(_ kind: AuditFinding.Kind) -> Bool {
  switch kind {
  case .weak, .reused, .expired: return true
  case .old, .expiringSoon, .insecureURL: return false
  }
}

private func describe(_ kind: AuditFinding.Kind) -> String {
  switch kind {
  case .weak(let score): return "weak (score \(score)/4)"
  case .reused(let count): return "reused (\(count) accounts)"
  case .old(let since): return "old (unchanged since \(displayDate(since, time: false)))"
  case .expired(let on): return "expired \(displayDate(on, time: false))"
  case .expiringSoon(let on): return "expires \(displayDate(on, time: false))"
  case .insecureURL: return "http:// login URL"
  }
}
