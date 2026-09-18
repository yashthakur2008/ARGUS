import Foundation
import Security

/// Uses only the login keychain and one fixed generic-password identity.
/// All operations fail closed without UI. In particular, speech never triggers a prompt.
@MainActor final class NativeElevenLabsKeychain: ElevenLabsKeychainBoundary {
  static let service = "com.argus.development.elevenlabs"
  static let account = "voice-api-key"
  private let security: any ElevenLabsSecurityAPI

  init(security: any ElevenLabsSecurityAPI = SystemElevenLabsSecurityAPI()) {
    self.security = security
  }

  func read() throws -> Data? {
    var query = try matchQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, result) = security.copyMatching(query)
    if status == errSecItemNotFound { return nil }
    try Self.check(status)
    guard let data = result as? Data else { throw ElevenLabsCredentialError.invalidStoredValue }
    return data
  }

  func write(_ data: Data) throws {
    let keychain = try security.openLoginKeychain()
    // Always supply the current application explicitly rather than relying on implicit defaults.
    let access = try security.currentApplicationOnlyAccess()
    var item = identity
    item[kSecUseKeychain as String] = keychain
    item[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    item[kSecAttrAccess as String] = access
    item[kSecValueData as String] = data
    let status = security.add(item)
    if status == errSecDuplicateItem {
      let query = matchQuery(keychain: keychain)
      // Replace the ACL together with the value. Never delete/re-add on failure.
      try Self.check(security.update(query, attributes: [
        kSecValueData as String: data, kSecAttrAccess as String: access,
      ]))
    } else {
      try Self.check(status)
    }
  }

  func remove() throws {
    let status = security.delete(try matchQuery())
    if status != errSecItemNotFound { try Self.check(status) }
  }

  private var identity: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.account]
  }
  private func matchQuery() throws -> [String: Any] {
    matchQuery(keychain: try security.openLoginKeychain())
  }
  private func matchQuery(keychain: CFTypeRef) -> [String: Any] {
    var query = identity
    query[kSecMatchSearchList as String] = [keychain]
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    return query
  }
  static func check(_ status: OSStatus) throws {
    switch status {
    case errSecSuccess: return
    case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
      throw ElevenLabsCredentialError.accessDenied
    case errSecNotAvailable, errSecNoSuchKeychain, errSecInvalidKeychain:
      throw ElevenLabsCredentialError.unavailable
    default: throw ElevenLabsCredentialError.operationFailed
    }
  }
}

/// Injectable Security boundary. Unit tests supply opaque fake handles and never call Security.
@MainActor protocol ElevenLabsSecurityAPI {
  func openLoginKeychain() throws -> CFTypeRef
  func currentApplicationOnlyAccess() throws -> CFTypeRef
  func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
  func add(_ attributes: [String: Any]) -> OSStatus
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
  func delete(_ query: [String: Any]) -> OSStatus
}

@MainActor private final class SystemElevenLabsSecurityAPI: ElevenLabsSecurityAPI {
  func openLoginKeychain() throws -> CFTypeRef {
    var keychain: SecKeychain?
    // Do not use the user's mutable default keychain or create a missing keychain.
    let path = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Keychains/login.keychain-db").path
    try NativeElevenLabsKeychain.check(SecKeychainOpen(path, &keychain))
    guard let keychain else { throw ElevenLabsCredentialError.unavailable }
    return keychain
  }

  func currentApplicationOnlyAccess() throws -> CFTypeRef {
    var application: SecTrustedApplication?
    // A nil path means this process, not a wildcard trust entry.
    try NativeElevenLabsKeychain.check(SecTrustedApplicationCreateFromPath(nil, &application))
    guard let application else { throw ElevenLabsCredentialError.unavailable }
    var access: SecAccess?
    try NativeElevenLabsKeychain.check(SecAccessCreate(
      "ARGUS ElevenLabs voice credential" as CFString, [application] as CFArray, &access))
    guard let access else { throw ElevenLabsCredentialError.unavailable }
    return access
  }

  func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return (status, result)
  }
  func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
  }
  func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}
