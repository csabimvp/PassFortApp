import Foundation
import PassFortCrypto

// Uncomment the next line, run `swift build`, and it fails to compile.
// That failure IS the §4 layering guarantee -- PassFortVault cannot see PFCrypto.
// import PFCrypto

public enum Vault {
  /// Proves the allowed direction: PassFortVault -> PassFortCrypto (pure Swift API).
  public static func seamSelfTest(_ probe: Data) throws -> Data {
    try echo(probe)
  }
}
