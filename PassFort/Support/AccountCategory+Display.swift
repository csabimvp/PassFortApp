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
}
