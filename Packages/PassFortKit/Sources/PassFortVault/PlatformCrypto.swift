import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#elseif os(Linux)
  import CLinuxTLS
#endif

/// SHA-256 and HMAC for the code that needs them outside the vault's crypto: the SPKI pin hash and
/// one-time codes. CryptoKit on Apple platforms, OpenSSL's libcrypto on Linux (ADR-0011). Neither
/// input is key material -- a public certificate and a TOTP seed, which is record payload -- so
/// ADR-0004's "only `PFCrypto` holds keys" is untouched.
enum PlatformCrypto {
  static func sha256(_ data: Data) -> Data {
    #if canImport(CryptoKit)
      Data(SHA256.hash(data: data))
    #else
      var digest = [UInt8](repeating: 0, count: 32)
      let ok = data.withUnsafeBytes { bytes in
        pf_sha256(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &digest)
      }
      // Fails only on a NULL with a non-zero length, which withUnsafeBytes never passes.
      precondition(ok == 1, "libcrypto SHA-256 failed")
      return Data(digest)
    #endif
  }

  static func hmac(_ algorithm: TOTPAlgorithm, key: Data, message: Data) -> Data {
    #if canImport(CryptoKit)
      let key = SymmetricKey(data: key)
      switch algorithm {
      case .sha1: return Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
      case .sha256: return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
      case .sha512: return Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
      }
    #else
      let alg: Int32 =
        switch algorithm {
        case .sha1: 1
        case .sha256: 256
        case .sha512: 512
        }
      var mac = [UInt8](repeating: 0, count: 64)
      let length = key.withUnsafeBytes { keyBytes in
        message.withUnsafeBytes { messageBytes in
          pf_hmac(
            alg, keyBytes.bindMemory(to: UInt8.self).baseAddress, keyBytes.count,
            messageBytes.bindMemory(to: UInt8.self).baseAddress, messageBytes.count, &mac,
            mac.count)
        }
      }
      // Fails only on bad input (an unknown algorithm, a NULL with a length), not on any key.
      precondition(length > 0, "libcrypto HMAC failed")
      return Data(mac.prefix(length))
    #endif
  }
}
