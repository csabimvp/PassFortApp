import Foundation

/// Import from Password Safe's plain-text export (File ▸ Export To ▸ Plain Text): tab-separated,
/// one header row, one account per line.
///
/// Columns are found by **name**, so a file with fewer columns, or in another order, still works;
/// only `Group/Title` is required. What maps onto `AccountPayload`:
///
/// | Password Safe | PassFort |
/// |---|---|
/// | `Group/Title` | `title`; the group path (`Banking.UK`) becomes one tag, `Banking/UK` |
/// | `Username`, `e-mail`, `Password`, `URL`, `Notes` | the same fields |
/// | `Two Factor Key`, `TOTP Length`, `TOTP Time Step` | `totp` |
/// | `Created Time`, `Password Modified Time`, `Password Expiry Date` | `createdAt`, `passwordChangedAt`, `expiresAt` |
/// | `History` | `passwordHistory` |
///
/// Everything else (AutoType, Run Command, DCA, policies, …) has no home in the model; a column
/// that held a value is named in `ImportPlan.ignoredColumns`, so nothing is dropped silently.
///
/// Password Safe writes `»` where a title holds a literal `.` (the dot separates groups) and where
/// notes hold a line break; both are undone here.
public enum PasswordSafeImport {

  public enum Failure: Error, Equatable {
    /// Not UTF-8 text.
    case notText
    /// No header row with a `Group/Title` column -- not a Password Safe text export.
    case notPasswordSafeExport
  }

  /// Parse an export. Throws only when the file as a whole is unusable; a bad row is skipped and
  /// reported in the plan instead.
  public static func plan(_ data: Data, timeZone: TimeZone = .current) throws -> ImportPlan {
    guard var text = String(data: data, encoding: .utf8) else { throw Failure.notText }
    if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

    let rows = TabSeparated.rows(text)
    guard let header = rows.first, header.contains(Column.groupTitle) else {
      throw Failure.notPasswordSafeExport
    }
    let index = Dictionary(
      header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces), $0) },
      uniquingKeysWith: { first, _ in first })
    let mapper = RowMapper(columns: index, timeZone: timeZone)

    var plan = ImportPlan()
    for (offset, fields) in rows.dropFirst().enumerated() {
      let line = offset + 2  // 1-based, after the header
      if fields.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
      switch mapper.payload(from: fields) {
      case .success(let mapped):
        plan.accounts.append(ImportedAccount(line: line, payload: mapped.payload))
        plan.warnings += mapped.warnings.map { "line \(line): \($0)" }
      case .failure(let reason):
        plan.skipped.append(ImportPlan.Skip(line: line, reason: reason.message))
      }
      for name in mapper.ignoredColumnsWithValues(in: fields) {
        plan.ignoredColumns[name, default: 0] += 1
      }
    }
    return plan
  }

  // MARK: - Columns

  enum Column {
    static let groupTitle = "Group/Title"
    static let username = "Username"
    static let password = "Password"
    static let twoFactorKey = "Two Factor Key"
    static let totpConfig = "TOTP Config"
    static let totpStartTime = "TOTP Start Time"
    static let totpTimeStep = "TOTP Time Step"
    static let totpLength = "TOTP Length"
    static let url = "URL"
    static let createdTime = "Created Time"
    static let passwordModifiedTime = "Password Modified Time"
    static let passwordExpiryDate = "Password Expiry Date"
    static let history = "History"
    static let email = "e-mail"
    static let notes = "Notes"

    static let mapped: Set<String> = [
      groupTitle, username, password, twoFactorKey, totpConfig, totpStartTime, totpTimeStep,
      totpLength, url, createdTime, passwordModifiedTime, passwordExpiryDate, history, email, notes,
    ]
    /// Columns Password Safe always fills, whose values carry nothing to keep: the record's own
    /// bookkeeping (it is re-stamped on import) and flags with a default that means "unset".
    static let bookkeeping: Set<String> = ["Last Access Time", "Record Modified Time"]
    static let unsetDefaults: [String: Set<String>] = [
      "DCA": ["-1"], "Shift+DCA": ["-1"], "Protected": ["N"], "Password Expiry Interval": ["0"],
    ]
  }

  /// `»` is Password Safe's export stand-in for `.` in names and for line breaks in notes.
  static let delimiter: Character = "»"

  // MARK: - Rows

  struct RowFailure: Error {
    let message: String
  }

  struct MappedRow {
    var payload: AccountPayload
    var warnings: [String]
  }

  struct RowMapper {
    let columns: [String: Int]
    let timeZone: TimeZone

    private func value(_ name: String, in fields: [String]) -> String? {
      guard let index = columns[name], index < fields.count else { return nil }
      let trimmed = fields[index].trimmingCharacters(in: .whitespaces)
      return trimmed.isEmpty ? nil : trimmed
    }

    func payload(from fields: [String]) -> Result<MappedRow, RowFailure> {
      guard let groupTitle = value(Column.groupTitle, in: fields) else {
        return .failure(RowFailure(message: "no Group/Title"))
      }
      let (group, title) = PasswordSafeImport.splitGroupTitle(groupTitle)
      guard !title.isEmpty else { return .failure(RowFailure(message: "empty title")) }

      var warnings: [String] = []
      var payload = AccountPayload(title: title)
      payload.username = value(Column.username, in: fields)
      payload.password = value(Column.password, in: fields)
      payload.email = value(Column.email, in: fields)
      payload.notes = value(Column.notes, in: fields).map(PasswordSafeImport.notes)
      if let group { payload.tags = [group] }

      if let raw = value(Column.url, in: fields) {
        if let url = PasswordSafeImport.url(raw) {
          payload.urls = [url]
        } else {
          warnings.append("URL kept in notes, it doesn't parse")
          payload.notes = [payload.notes, "URL: \(raw)"].compactMap { $0 }.joined(separator: "\n")
        }
      }

      let now = Date()
      if let created = date(Column.createdTime, in: fields) { payload.createdAt = created }
      payload.passwordChangedAt = date(Column.passwordModifiedTime, in: fields)
      payload.expiresAt = date(Column.passwordExpiryDate, in: fields)
      if payload.createdAt > now { payload.createdAt = now }

      if let key = value(Column.twoFactorKey, in: fields) {
        switch oneTimeCode(key: key, fields: fields) {
        case .success(let config): payload.totp = config
        case .failure(let failure):
          warnings.append("one-time code not imported (\(failure.message))")
        }
      }

      if let raw = value(Column.history, in: fields) {
        if let history = PasswordSafeImport.passwordHistory(raw) {
          payload.passwordHistory = history
        } else {
          warnings.append("password history not imported (unrecognised format)")
        }
      }

      let hasLogin = payload.password != nil || payload.username != nil || !payload.urls.isEmpty
      if !hasLogin, payload.notes != nil { payload.category = .secureNote }
      return .success(MappedRow(payload: payload, warnings: warnings))
    }

    private func oneTimeCode(key: String, fields: [String]) -> Result<TOTPConfig, RowFailure> {
      guard var config = try? TOTPConfig(parsing: key) else {
        return .failure(RowFailure(message: "the key isn't Base32"))
      }
      // Password Safe's TOTP Config 0 is its default (SHA-1); anything else isn't documented.
      if let raw = value(Column.totpConfig, in: fields), raw != "0" {
        return .failure(RowFailure(message: "unsupported TOTP Config \(raw)"))
      }
      if let raw = value(Column.totpStartTime, in: fields), raw != "0", !raw.hasPrefix("1970") {
        return .failure(RowFailure(message: "a custom TOTP start time isn't supported"))
      }
      if let raw = value(Column.totpLength, in: fields) {
        guard let digits = Int(raw), (6...10).contains(digits) else {
          return .failure(RowFailure(message: "TOTP Length \(raw)"))
        }
        config.digits = digits
      }
      if let raw = value(Column.totpTimeStep, in: fields) {
        guard let period = Int(raw), period > 0 else {
          return .failure(RowFailure(message: "TOTP Time Step \(raw)"))
        }
        config.period = period
      }
      return .success(config)
    }

    private func date(_ name: String, in fields: [String]) -> Date? {
      value(name, in: fields).flatMap { PasswordSafeImport.date($0, timeZone: timeZone) }
    }

    /// Columns this mapper doesn't use that hold a meaningful value in `fields`.
    func ignoredColumnsWithValues(in fields: [String]) -> [String] {
      columns.compactMap { name, _ in
        guard !Column.mapped.contains(name), !Column.bookkeeping.contains(name),
          let raw = value(name, in: fields)
        else { return nil }
        if Column.unsetDefaults[name]?.contains(raw) == true { return nil }
        return name
      }
      .sorted()
    }
  }

  // MARK: - Field conversions

  /// `Banking.UK.HSBC` → (`Banking/UK`, `HSBC`); `Amazon»co»uk` → (nil, `Amazon.co.uk`).
  static func splitGroupTitle(_ raw: String) -> (group: String?, title: String) {
    var parts = raw.split(separator: ".", omittingEmptySubsequences: false).map {
      String($0).replacingOccurrences(of: String(delimiter), with: ".")
        .trimmingCharacters(in: .whitespaces)
    }
    let title = parts.removeLast()
    let group = parts.filter { !$0.isEmpty }.joined(separator: "/")
    return (group.isEmpty ? nil : group, title)
  }

  static func notes(_ raw: String) -> String {
    raw.replacingOccurrences(of: String(delimiter), with: "\n")
  }

  /// A URL with a scheme as-is; a bare host (`www.example.com/login`) gets `https://`.
  static func url(_ raw: String) -> URL? {
    if raw.contains("://"), let url = URL(string: raw), url.scheme != nil { return url }
    guard !raw.contains(" "), raw.contains("."), let url = URL(string: "https://" + raw),
      url.host() != nil
    else { return nil }
    return url
  }

  /// `2025/02/14 13:39:24`, in the exporting Mac's local time.
  static func date(_ raw: String, timeZone: TimeZone) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    for format in ["yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd"] {
      formatter.dateFormat = format
      if let date = formatter.date(from: raw) { return date }
    }
    return nil
  }

  /// Password Safe's history field: `f mm nn` (status, max kept, count -- one, two, two hex
  /// digits), then `count` entries of an 8-hex-digit Unix time, a 4-hex-digit length, and the old
  /// password. `00000` is "no history". `nil` when the text doesn't follow that shape.
  static func passwordHistory(_ raw: String) -> [PasswordHistoryEntry]? {
    let characters = Array(raw.filter { $0 != " " })
    guard characters.count >= 5, let count = Int(String(characters[3..<5]), radix: 16) else {
      return nil
    }
    var entries: [PasswordHistoryEntry] = []
    var cursor = 5
    for _ in 0..<count {
      guard cursor + 12 <= characters.count,
        let time = Int(String(characters[cursor..<cursor + 8]), radix: 16),
        let length = Int(String(characters[cursor + 8..<cursor + 12]), radix: 16),
        cursor + 12 + length <= characters.count
      else { return nil }
      let password = String(characters[cursor + 12..<cursor + 12 + length])
      entries.append(
        PasswordHistoryEntry(
          password: password, replacedAt: Date(timeIntervalSince1970: TimeInterval(time))))
      cursor += 12 + length
    }
    guard cursor == characters.count else { return nil }
    // Newest first, like `passwordHistory` everywhere else (§7.2).
    return entries.sorted { $0.replacedAt > $1.replacedAt }
  }
}

// MARK: - The plan

/// What an import would do, before anything is written: the accounts, the rows it couldn't use,
/// and what it noticed along the way. Holds plaintext secrets -- keep it only while needed.
public struct ImportPlan: Sendable {
  public struct Skip: Sendable, Equatable {
    public let line: Int
    public let reason: String
  }

  public var accounts: [ImportedAccount] = []
  public var skipped: [Skip] = []
  public var warnings: [String] = []
  /// Unmapped columns that held a value, and in how many rows.
  public var ignoredColumns: [String: Int] = [:]

  /// Indices into `accounts` that look like an account already in the vault: the same title or
  /// host, with the same username (or email). Compared case-insensitively.
  public func duplicates(of existing: [AccountSummary]) -> Set<Int> {
    func key(_ name: String?, _ user: String?) -> String? {
      guard let name, !name.isEmpty else { return nil }
      return name.lowercased() + "\u{0}" + (user ?? "").lowercased()
    }
    var known = Set<String>()
    for summary in existing where !summary.isDeleted {
      for name in [summary.title, summary.host] {
        if let k = key(name, summary.username) { known.insert(k) }
      }
    }
    var found = Set<Int>()
    for (index, imported) in accounts.enumerated() {
      let payload = imported.payload
      let user = payload.username ?? payload.email
      let names = [payload.title, payload.urls.first?.host()]
      if names.contains(where: { key($0, user).map(known.contains) ?? false }) {
        found.insert(index)
      }
    }
    return found
  }
}

/// One account to import, with the line it came from (for messages).
public struct ImportedAccount: Sendable {
  public let line: Int
  public var payload: AccountPayload
}

// MARK: - Tab-separated text

/// Tab-separated rows with CSV-style quoting: a field that starts with `"` runs to the next
/// unpaired `"` (and may then contain tabs or line breaks); `""` inside it is one `"`. Line ends
/// may be `\n` or `\r\n`.
enum TabSeparated {
  static func rows(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var atFieldStart = true
    var characters = text.makeIterator()
    var pending: Character? = characters.next()

    while let character = pending {
      pending = characters.next()
      if quoted {
        if character == "\"" {
          if pending == "\"" {
            field.append("\"")
            pending = characters.next()
          } else {
            quoted = false
          }
        } else {
          field.append(character)
        }
        continue
      }
      switch character {
      case "\"" where atFieldStart:
        quoted = true
        atFieldStart = false
      case "\t":
        row.append(field)
        field = ""
        atFieldStart = true
      case "\n", "\r\n", "\r":
        row.append(field)
        rows.append(row)
        row = []
        field = ""
        atFieldStart = true
      default:
        field.append(character)
        atFieldStart = false
      }
    }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }
    return rows
  }
}
