import Foundation

/// The plaintext of §5.4: serialized to JSON, padded (§14.7), then sealed. Never
/// parsed in SQL, never crosses into `PassFortCrypto` as anything but bytes.
///
/// The JSON keys are **on-disk format** — snake_case, pinned by `CodingKeys`.
/// Renaming a Swift property costs nothing; renaming a key is a format change
/// (schema bump + ADR + re-seal migration). The decoder is deliberately
/// permissive: unrecognised keys land in `unknown` and are written back verbatim.
public struct AccountPayload: Sendable, Equatable {
  public var schemaVersion: UInt16

  // Core credential
  public var title: String  // the one always-required field
  public var username: String?
  public var password: String?
  public var email: String?
  public var urls: [URL]
  public var notes: String?

  // Additional factors
  public var totp: TOTPConfig?
  public var securityQuestions: [SecurityQuestion]
  public var memorableWord: String?
  public var pin: String?
  public var recoveryCodes: [String]

  // Lifecycle -- encrypted metadata, deliberately not envelope columns
  public var createdAt: Date
  public var passwordChangedAt: Date?
  public var passwordHistory: [PasswordHistoryEntry]
  public var revisionHistory: [RevisionEntry]  // which fields changed, per version (§7.2 / §7.7)
  public var usedAt: Date?  // see the write-amplification note (§7.2)
  public var expiresAt: Date?

  // Organisation / UX
  public var category: AccountCategory
  public var tags: [String]
  public var favorite: Bool
  public var iconHint: String?

  // Audit -- computed client-side, cached in the record
  public var strength: PasswordStrength?
  public var breach: BreachStatus

  // Extensibility
  public var customFields: [CustomField]
  public var conflictOf: UUID?

  // Forward-compat: keys a newer schema wrote (§7.2)
  public var unknown: [String: JSONValue]

  public init(
    schemaVersion: UInt16 = 1,
    title: String,
    username: String? = nil,
    password: String? = nil,
    email: String? = nil,
    urls: [URL] = [],
    notes: String? = nil,
    totp: TOTPConfig? = nil,
    securityQuestions: [SecurityQuestion] = [],
    memorableWord: String? = nil,
    pin: String? = nil,
    recoveryCodes: [String] = [],
    createdAt: Date = Date(),
    passwordChangedAt: Date? = nil,
    passwordHistory: [PasswordHistoryEntry] = [],
    revisionHistory: [RevisionEntry] = [],
    usedAt: Date? = nil,
    expiresAt: Date? = nil,
    category: AccountCategory = .login,
    tags: [String] = [],
    favorite: Bool = false,
    iconHint: String? = nil,
    strength: PasswordStrength? = nil,
    breach: BreachStatus = .unchecked,
    customFields: [CustomField] = [],
    conflictOf: UUID? = nil,
    unknown: [String: JSONValue] = [:]
  ) {
    self.schemaVersion = schemaVersion
    self.title = title
    self.username = username
    self.password = password
    self.email = email
    self.urls = urls
    self.notes = notes
    self.totp = totp
    self.securityQuestions = securityQuestions
    self.memorableWord = memorableWord
    self.pin = pin
    self.recoveryCodes = recoveryCodes
    self.createdAt = createdAt
    self.passwordChangedAt = passwordChangedAt
    self.passwordHistory = passwordHistory
    self.revisionHistory = revisionHistory
    self.usedAt = usedAt
    self.expiresAt = expiresAt
    self.category = category
    self.tags = tags
    self.favorite = favorite
    self.iconHint = iconHint
    self.strength = strength
    self.breach = breach
    self.customFields = customFields
    self.conflictOf = conflictOf
    self.unknown = unknown
  }
}

// MARK: - Codable with the forward-compat bag

extension AccountPayload: Codable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion = "schema_version"
    case title
    case username
    case password
    case email
    case urls
    case notes
    case totp
    case securityQuestions = "security_questions"
    case memorableWord = "memorable_word"
    case pin
    case recoveryCodes = "recovery_codes"
    case createdAt = "created_at"
    case passwordChangedAt = "password_changed_at"
    case passwordHistory = "password_history"
    case revisionHistory = "revision_history"
    case usedAt = "used_at"
    case expiresAt = "expires_at"
    case category
    case tags
    case favorite
    case iconHint = "icon_hint"
    case strength
    case breach
    case customFields = "custom_fields"
    case conflictOf = "conflict_of"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(UInt16.self, forKey: .schemaVersion)
    title = try container.decode(String.self, forKey: .title)
    username = try container.decodeIfPresent(String.self, forKey: .username)
    password = try container.decodeIfPresent(String.self, forKey: .password)
    email = try container.decodeIfPresent(String.self, forKey: .email)
    urls = try container.decodeIfPresent([URL].self, forKey: .urls) ?? []
    notes = try container.decodeIfPresent(String.self, forKey: .notes)
    totp = try container.decodeIfPresent(TOTPConfig.self, forKey: .totp)
    securityQuestions =
      try container.decodeIfPresent([SecurityQuestion].self, forKey: .securityQuestions) ?? []
    memorableWord = try container.decodeIfPresent(String.self, forKey: .memorableWord)
    pin = try container.decodeIfPresent(String.self, forKey: .pin)
    recoveryCodes = try container.decodeIfPresent([String].self, forKey: .recoveryCodes) ?? []
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    passwordChangedAt = try container.decodeIfPresent(Date.self, forKey: .passwordChangedAt)
    passwordHistory =
      try container.decodeIfPresent([PasswordHistoryEntry].self, forKey: .passwordHistory) ?? []
    revisionHistory =
      try container.decodeIfPresent([RevisionEntry].self, forKey: .revisionHistory) ?? []
    usedAt = try container.decodeIfPresent(Date.self, forKey: .usedAt)
    expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    category = try container.decodeIfPresent(AccountCategory.self, forKey: .category) ?? .login
    tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
    iconHint = try container.decodeIfPresent(String.self, forKey: .iconHint)
    strength = try container.decodeIfPresent(PasswordStrength.self, forKey: .strength)
    breach = try container.decodeIfPresent(BreachStatus.self, forKey: .breach) ?? .unchecked
    customFields = try container.decodeIfPresent([CustomField].self, forKey: .customFields) ?? []
    conflictOf = try container.decodeIfPresent(UUID.self, forKey: .conflictOf)

    // Everything the known keys didn't claim.
    let known = Set(CodingKeys.allCases.map(\.stringValue))
    let dynamic = try decoder.container(keyedBy: DynamicCodingKey.self)
    var extras: [String: JSONValue] = [:]
    for key in dynamic.allKeys where !known.contains(key.stringValue) {
      extras[key.stringValue] = try dynamic.decode(JSONValue.self, forKey: key)
    }
    unknown = extras
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(title, forKey: .title)
    try container.encodeIfPresent(username, forKey: .username)
    try container.encodeIfPresent(password, forKey: .password)
    try container.encodeIfPresent(email, forKey: .email)
    if !urls.isEmpty { try container.encode(urls, forKey: .urls) }
    try container.encodeIfPresent(notes, forKey: .notes)
    try container.encodeIfPresent(totp, forKey: .totp)
    if !securityQuestions.isEmpty {
      try container.encode(securityQuestions, forKey: .securityQuestions)
    }
    try container.encodeIfPresent(memorableWord, forKey: .memorableWord)
    try container.encodeIfPresent(pin, forKey: .pin)
    if !recoveryCodes.isEmpty { try container.encode(recoveryCodes, forKey: .recoveryCodes) }
    try container.encode(createdAt, forKey: .createdAt)
    try container.encodeIfPresent(passwordChangedAt, forKey: .passwordChangedAt)
    if !passwordHistory.isEmpty { try container.encode(passwordHistory, forKey: .passwordHistory) }
    if !revisionHistory.isEmpty { try container.encode(revisionHistory, forKey: .revisionHistory) }
    try container.encodeIfPresent(usedAt, forKey: .usedAt)
    try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
    try container.encode(category, forKey: .category)
    if !tags.isEmpty { try container.encode(tags, forKey: .tags) }
    if favorite { try container.encode(favorite, forKey: .favorite) }
    try container.encodeIfPresent(iconHint, forKey: .iconHint)
    try container.encodeIfPresent(strength, forKey: .strength)
    if breach != .unchecked { try container.encode(breach, forKey: .breach) }
    if !customFields.isEmpty { try container.encode(customFields, forKey: .customFields) }
    try container.encodeIfPresent(conflictOf, forKey: .conflictOf)

    var dynamic = encoder.container(keyedBy: DynamicCodingKey.self)
    for (key, value) in unknown {
      try dynamic.encode(value, forKey: DynamicCodingKey(key))
    }
  }
}
