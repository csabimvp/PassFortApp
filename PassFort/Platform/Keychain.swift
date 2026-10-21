import Foundation
import LocalAuthentication
import Security

/// A thin wrapper over `kSecClassGenericPassword` in the app's own (default) access group, in the
/// data-protection keychain. Every item is `…WhenPasscodeSetThisDeviceOnly`: nothing PassFort puts
/// in the Keychain is ever iCloud-synced.
///
/// Logs nothing. Failures carry an `OSStatus`, never a value (§13.1).
nonisolated enum Keychain {
  enum Failure: Error, Equatable {
    case status(OSStatus)
    case unexpectedData
    case userCancelled
    case biometryUnavailable
  }

  // MARK: - Plain items

  /// Insert or replace. For the anti-rollback mark and the device id.
  static func set(_ data: Data, service: String, account: String) throws {
    let update = SecItemUpdate(
      identity(service: service, account: account) as CFDictionary,
      [kSecValueData: data] as CFDictionary)
    switch update {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var item = identity(service: service, account: account)
      item[kSecValueData] = data
      item[kSecAttrAccessible] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
      try check(SecItemAdd(item as CFDictionary, nil))
    default:
      throw Failure.status(update)
    }
  }

  /// `nil` when there is no such item.
  static func get(service: String, account: String) throws -> Data? {
    var query = identity(service: service, account: account)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    return try copy(query)
  }

  /// Deleting an absent item is not an error.
  static func delete(service: String, account: String) throws {
    let status = SecItemDelete(identity(service: service, account: account) as CFDictionary)
    if status != errSecItemNotFound { try check(status) }
  }

  // MARK: - Biometry-gated items

  /// Insert or replace an item that only a Touch ID match releases. `.biometryCurrentSet`, not
  /// `.biometryAny`: enrolling or removing a fingerprint invalidates the item (ADR-0008).
  ///
  /// The access control cannot be changed on an existing item, so this deletes then adds.
  static func setBiometryGated(_ data: Data, service: String, account: String) throws {
    guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    else { throw Failure.biometryUnavailable }

    var error: Unmanaged<CFError>?
    guard
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error)
    else {
      throw Failure.status(OSStatus(CFErrorGetCode(error?.takeRetainedValue())))
    }

    try delete(service: service, account: account)
    var item = identity(service: service, account: account)
    item[kSecValueData] = data
    item[kSecAttrAccessControl] = access
    try check(SecItemAdd(item as CFDictionary, nil))
  }

  /// Shows the Touch ID sheet with `prompt` as its reason. `nil` when there is no such item, which
  /// is also what a fingerprint change looks like once the item has been invalidated.
  ///
  /// - Throws: `.userCancelled` when the user backs out of the sheet.
  static func getBiometryGated(
    service: String, account: String, prompt: String, context: LAContext = LAContext()
  ) throws -> Data? {
    context.localizedReason = prompt
    var query = identity(service: service, account: account)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext] = context
    return try copy(query)
  }

  // MARK: - Helpers

  private static func identity(service: String, account: String) -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecAttrSynchronizable: false,
      kSecUseDataProtectionKeychain: true,
    ]
  }

  private static func copy(_ query: [CFString: Any]) throws -> Data? {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else { throw Failure.unexpectedData }
      return data
    case errSecItemNotFound:
      return nil
    case errSecUserCanceled:
      throw Failure.userCancelled
    default:
      throw Failure.status(status)
    }
  }

  private static func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else { throw Failure.status(status) }
  }
}
