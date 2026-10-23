import Foundation

/// The password-health audit (§7.5 `AuditFinding`): weak, reused, old, expiring and `http://`
/// findings, computed on demand from the decrypted vault and never stored.
///
/// `VaultRepository.audit` runs it **inside the actor**: the decrypted payloads never leave it in
/// bulk, only these findings do -- account ids and what is wrong, no secret values. Strength is
/// estimated fresh each time rather than cached in `AccountPayload.strength`, which would re-seal
/// every record (the `usedAt` write-amplification trap, §7.2).

// MARK: - Findings

public struct AuditFinding: Sendable, Equatable, Hashable {
  public enum Kind: Sendable, Equatable, Hashable {
    /// Estimated strength below `PasswordAudit.weakBelow` (score 0-4).
    case weak(score: Int)
    /// The same password is used by `count` live accounts, this one included.
    case reused(count: Int)
    /// The password has not changed since `since` (its `passwordChangedAt`, else `createdAt`).
    case old(since: Date)
    /// `expiresAt` is in the past.
    case expired(on: Date)
    /// `expiresAt` falls within `PasswordAudit.expiringWithin`.
    case expiringSoon(on: Date)
    /// A login URL that is plain `http://`.
    case insecureURL
  }

  public var kind: Kind
  public var account: UUID

  public init(kind: Kind, account: UUID) {
    self.kind = kind
    self.account = account
  }
}

// MARK: - The audit

public enum PasswordAudit {
  /// A score below this is reported as weak -- zxcvbn's own "too guessable" line.
  public static let weakBelow = 3
  /// Passwords unchanged for longer than this are reported as old.
  public static let oldAfter: TimeInterval = 365 * 24 * 3600
  /// An expiry this close is reported ahead of time.
  public static let expiringWithin: TimeInterval = 30 * 24 * 3600

  /// Every finding for `accounts` (tombstones are skipped), ordered by account then kind.
  public static func run(_ accounts: [Account], now: Date = Date()) -> [AuditFinding] {
    let live = accounts.filter { !$0.isDeleted }

    var byPassword: [String: Int] = [:]
    for account in live {
      if let password = account.payload.password, !password.isEmpty {
        byPassword[password, default: 0] += 1
      }
    }

    var findings: [AuditFinding] = []
    for account in live {
      let payload = account.payload
      func add(_ kind: AuditFinding.Kind) {
        findings.append(AuditFinding(kind: kind, account: account.id))
      }

      if let password = payload.password, !password.isEmpty {
        let score = PasswordStrength.estimate(password).score
        if score < weakBelow { add(.weak(score: score)) }
        if let count = byPassword[password], count > 1 { add(.reused(count: count)) }
        let since = payload.passwordChangedAt ?? payload.createdAt
        if now.timeIntervalSince(since) > oldAfter { add(.old(since: since)) }
      }
      if let expiry = payload.expiresAt {
        if expiry < now {
          add(.expired(on: expiry))
        } else if expiry.timeIntervalSince(now) < expiringWithin {
          add(.expiringSoon(on: expiry))
        }
      }
      if payload.urls.contains(where: { $0.scheme?.lowercased() == "http" }) { add(.insecureURL) }
    }
    return findings
  }
}

extension VaultRepository {
  /// Run the audit over every record. Decrypts the whole vault inside the actor and returns only
  /// the findings -- no password value crosses out.
  public func audit(now: Date = Date()) async throws -> [AuditFinding] {
    PasswordAudit.run(try await allAccounts(), now: now)
  }
}

// MARK: - Strength estimate

extension PasswordStrength {
  /// A rough, offline guessability estimate on zxcvbn's 0-4 scale -- not a port of zxcvbn. It
  /// counts the character pool, collapses repeats, sequences (`abc`, `321`) and keyboard runs
  /// (`qwerty`) to a single character each, and treats a common password -- after undoing simple
  /// l33t substitutions and stripping trailing digits/symbols -- as about a thousand guesses.
  /// Good enough to flag `Password1!` and `hunter2`; not a measure of a passphrase's real entropy.
  public static func estimate(_ password: String) -> PasswordStrength {
    let characters = Array(password)
    guard !characters.isEmpty else { return PasswordStrength(score: 0, guessesLog10: 0) }

    var pool = 0
    if characters.contains(where: \.isLowercase) { pool += 26 }
    if characters.contains(where: \.isUppercase) { pool += 26 }
    if characters.contains(where: \.isNumber) { pool += 10 }
    if characters.contains(where: { !$0.isLetter && !$0.isNumber }) { pool += 33 }
    pool = max(pool, 10)

    var guessesLog10 = Double(effectiveLength(characters)) * log10(Double(pool))

    let (base, tail) = splitCommonBase(password)
    if commonPasswords.contains(base) {
      // ~1,000 guesses for the base, plus the decorations bolted on after it.
      let tailLog10 = Double(effectiveLength(Array(tail))) * log10(Double(pool))
      guessesLog10 = min(guessesLog10, 3 + tailLog10)
    }

    let score: Int
    switch guessesLog10 {
    case ..<3: score = 0
    case ..<6: score = 1
    case ..<8: score = 2
    case ..<10: score = 3
    default: score = 4
    }
    return PasswordStrength(score: score, guessesLog10: guessesLog10)
  }

  /// Length with each repeat, sequence or keyboard run of 3+ counted once. A run is one kind of
  /// step throughout -- `aaab` is a repeat then a lone `b`, not one run.
  static func effectiveLength(_ characters: [Character]) -> Int {
    let lowered = characters.map { Character($0.lowercased()) }
    var length = 0
    var index = 0
    while index < lowered.count {
      var end = index + 1
      if end < lowered.count, let kind = step(lowered[index], lowered[end]) {
        while end < lowered.count, step(lowered[end - 1], lowered[end]) == kind { end += 1 }
      }
      length += (end - index >= 3) ? 1 : (end - index)
      index = end
    }
    return length
  }

  private enum Step: Equatable {
    case repeated
    case alphabet(Int)  // +1 / -1
    case keyboard(row: Int, direction: Int)
  }

  private static let keyboardRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm", "1234567890"]

  /// How `b` follows `a`, if it is a pattern step at all.
  private static func step(_ a: Character, _ b: Character) -> Step? {
    if a == b { return .repeated }
    if let x = a.asciiValue, let y = b.asciiValue, a.isLetter == b.isLetter,
      a.isNumber == b.isNumber, abs(Int(x) - Int(y)) == 1
    {
      return .alphabet(Int(y) - Int(x))
    }
    for (row, keys) in keyboardRows.map(Array.init).enumerated() {
      if let i = keys.firstIndex(of: a), let j = keys.firstIndex(of: b), abs(i - j) == 1 {
        return .keyboard(row: row, direction: j - i)
      }
    }
    return nil
  }

  /// Lower-cased, l33t undone, with trailing digits and symbols split off: `P@ssw0rd123!` →
  /// (`password`, `123!`).
  static func splitCommonBase(_ password: String) -> (base: String, tail: String) {
    let leet: [Character: Character] = [
      "@": "a", "4": "a", "3": "e", "1": "i", "!": "i", "0": "o", "$": "s", "5": "s", "7": "t",
    ]
    let lowered = Array(password.lowercased())
    var cut = lowered.count
    while cut > 0, !lowered[cut - 1].isLetter { cut -= 1 }
    // A base that is all digits ("123456") keeps them: don't strip it to nothing.
    if cut == 0 { return (String(lowered), "") }
    let base = String(lowered[..<cut].map { leet[$0] ?? $0 })
    return (base, String(lowered[cut...]))
  }

  /// The most common passwords and password stems from public breach corpora -- enough to catch
  /// the obvious, not a dictionary attack.
  static let commonPasswords: Set<String> = [
    "password", "passw", "pass", "123456", "12345678", "123456789", "1234567890", "qwerty",
    "qwertyuiop", "abc123", "111111", "123123", "letmein", "welcome", "admin", "administrator",
    "login", "monkey", "dragon", "football", "baseball", "soccer", "hockey", "iloveyou", "princess",
    "sunshine", "master", "shadow", "superman", "batman", "trustno", "starwars", "whatever",
    "freedom", "hello", "secret", "charlie", "michael", "jennifer", "jordan", "hunter", "ranger",
    "buster", "tigger", "summer", "winter", "spring", "autumn", "flower", "cookie", "pokemon",
    "ninja", "mustang", "access", "changeme", "default", "guest", "test", "root", "user", "love",
    "qazwsx", "asdfgh", "zxcvbn", "passport", "computer", "internet", "samsung", "google", "apple",
    "chelsea", "liverpool", "arsenal", "london", "matrix", "killer", "pepper", "ginger", "orange",
    "banana", "cheese", "maggie", "daniel", "thomas", "andrew", "joshua", "george", "family",
  ]
}
