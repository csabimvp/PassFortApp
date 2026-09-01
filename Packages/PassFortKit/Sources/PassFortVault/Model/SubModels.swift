import Foundation

// Sub-models and enums from architecture.md §7.3 / §7.4 / §7.5. All Sendable
// value types; JSON keys pinned snake_case where they differ from the property.

// MARK: - Additional factors (§7.3)

public struct TOTPConfig: Codable, Sendable, Equatable {
  public var secret: Data  // base32-decoded shared seed
  public var algorithm: TOTPAlgorithm
  public var digits: Int
  public var period: Int  // seconds
  public var issuer: String?
  public var label: String?

  public init(
    secret: Data, algorithm: TOTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30,
    issuer: String? = nil, label: String? = nil
  ) {
    self.secret = secret
    self.algorithm = algorithm
    self.digits = digits
    self.period = period
    self.issuer = issuer
    self.label = label
  }
}

public struct SecurityQuestion: Codable, Sendable, Equatable {
  public var question: String
  public var answer: String
  public var caseSensitive: Bool

  enum CodingKeys: String, CodingKey {
    case question
    case answer
    case caseSensitive = "case_sensitive"
  }

  public init(question: String, answer: String, caseSensitive: Bool = false) {
    self.question = question
    self.answer = answer
    self.caseSensitive = caseSensitive
  }
}

public struct PasswordHistoryEntry: Codable, Sendable, Equatable {
  public var password: String
  public var replacedAt: Date

  enum CodingKeys: String, CodingKey {
    case password
    case replacedAt = "replaced_at"
  }

  public init(password: String, replacedAt: Date) {
    self.password = password
    self.replacedAt = replacedAt
  }
}

public struct CustomField: Codable, Sendable, Identifiable, Equatable {
  public var id: UUID
  public var label: String
  public var value: String
  public var kind: CustomFieldKind
  public var concealed: Bool

  public init(
    id: UUID = UUID(), label: String, value: String, kind: CustomFieldKind = .text,
    concealed: Bool = false
  ) {
    self.id = id
    self.label = label
    self.value = value
    self.kind = kind
    self.concealed = concealed
  }
}

public struct PasswordStrength: Codable, Sendable, Equatable {
  public var score: Int  // 0-4
  public var guessesLog10: Double

  enum CodingKeys: String, CodingKey {
    case score
    case guessesLog10 = "guesses_log10"
  }

  public init(score: Int, guessesLog10: Double) {
    self.score = score
    self.guessesLog10 = guessesLog10
  }
}

public enum AccountCategory: String, Codable, Sendable, CaseIterable {
  case login, bankAccount, paymentCard, identity, secureNote
  case wifi, softwareLicense, server, database, apiCredential, other
}

public enum CustomFieldKind: String, Codable, Sendable {
  case text, secret, url, email, phone, date, otp, boolean
}

public enum TOTPAlgorithm: String, Codable, Sendable {
  case sha1, sha256, sha512
}

public enum BreachStatus: Codable, Sendable, Equatable {
  case unchecked
  case clear(checkedAt: Date)
  case breached(count: Int, checkedAt: Date)
}

// MARK: - Vault-level models (§7.4)

/// Hybrid logical clock (§9.3). Ordering: wall time, then counter, then a stable
/// tiebreak on deviceID.
public struct HLC: Codable, Sendable, Comparable {
  public var wallMillis: UInt64
  public var counter: UInt32
  public var deviceID: UUID

  enum CodingKeys: String, CodingKey {
    case wallMillis = "wall_millis"
    case counter
    case deviceID = "device_id"
  }

  public init(wallMillis: UInt64, counter: UInt32, deviceID: UUID) {
    self.wallMillis = wallMillis
    self.counter = counter
    self.deviceID = deviceID
  }

  public static func now(device deviceID: UUID) -> HLC {
    HLC(
      wallMillis: UInt64(Date().timeIntervalSince1970 * 1000), counter: 0, deviceID: deviceID)
  }

  public static func < (lhs: HLC, rhs: HLC) -> Bool {
    if lhs.wallMillis != rhs.wallMillis { return lhs.wallMillis < rhs.wallMillis }
    if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
    return lhs.deviceID.uuidString < rhs.deviceID.uuidString
  }
}

/// The manifest MAC plus the version it covers (§5.5).
public struct ManifestState: Sendable, Equatable {
  public var vaultVersion: UInt64
  public var mac: Data  // 32B, from pf_mac_finish

  public init(vaultVersion: UInt64, mac: Data) {
    self.vaultVersion = vaultVersion
    self.mac = mac
  }
}

// MARK: - Derived, never sealed (§7.5)

/// The unlocked in-memory index (§3.4 / §8.3). Holds no secret -- no password,
/// no TOTP, no note, no security answer. Rebuilt on every unlock, dropped on lock.
public struct AccountSummary: Sendable, Identifiable, Equatable {
  public var id: UUID
  public var title: String
  public var username: String?
  public var host: String?
  public var tags: [String]
  public var favorite: Bool
  public var isConflict: Bool
  public var isDeleted: Bool

  public init(
    id: UUID, title: String, username: String? = nil, host: String? = nil, tags: [String] = [],
    favorite: Bool = false, isConflict: Bool = false, isDeleted: Bool = false
  ) {
    self.id = id
    self.title = title
    self.username = username
    self.host = host
    self.tags = tags
    self.favorite = favorite
    self.isConflict = isConflict
    self.isDeleted = isDeleted
  }
}
