import PassFortVault

/// GUI-only presentation labels — `AccountCategory` itself stays a plain,
/// presentation-free enum in `PassFortVault` (§7.3: "drives presentation, not
/// validation").
extension AccountCategory {
  var displayName: String {
    switch self {
    case .login: "Logins"
    case .bankAccount: "Bank Accounts"
    case .paymentCard: "Payment Cards"
    case .identity: "Identities"
    case .secureNote: "Secure Notes"
    case .wifi: "Wi-Fi"
    case .softwareLicense: "Software Licenses"
    case .server: "Servers"
    case .database: "Databases"
    case .apiCredential: "API Credentials"
    case .other: "Other"
    }
  }

  /// One item's category, for a form picker or a detail row ("Bank Account", not the
  /// sidebar's plural "Bank Accounts").
  var singularName: String {
    switch self {
    case .login: "Login"
    case .bankAccount: "Bank Account"
    case .paymentCard: "Payment Card"
    case .identity: "Identity"
    case .secureNote: "Secure Note"
    case .wifi: "Wi-Fi"
    case .softwareLicense: "Software License"
    case .server: "Server"
    case .database: "Database"
    case .apiCredential: "API Credential"
    case .other: "Other"
    }
  }
}
