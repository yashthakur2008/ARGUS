import Foundation
import Security
import Testing
@testable import ArgusPlatform

/// No SystemElevenLabsSecurityAPI or live keychain is used by these tests.
@Suite @MainActor struct NativeElevenLabsKeychainTests {
  @Test func readsUseFixedIdentityLoginSearchListAndNeverPrompt() throws {
    let security = FakeElevenLabsSecurity()
    let keychain = NativeElevenLabsKeychain(security: security)
    #expect(try keychain.read() == nil)
    let query = try #require(security.readQuery)
    assertFixedNoninteractiveQuery(query)
    #expect((query[kSecMatchSearchList as String] as? [String]) == ["fake-login-handle"])
    #expect(query[kSecReturnData as String] as? Bool == true)
    #expect(security.addCalls == 0)
  }
  @Test func writesUseCurrentApplicationACLAndExplicitLoginTarget() throws {
    let security = FakeElevenLabsSecurity()
    try NativeElevenLabsKeychain(security: security).write(Data("synthetic".utf8))
    let item = try #require(security.addQuery)
    assertFixedNoninteractiveQuery(item)
    #expect(item[kSecAttrAccess as String] as? String == "fake-current-app-only-access")
    #expect(item[kSecUseKeychain as String] as? String == "fake-login-handle")
    #expect(security.accessCalls == 1)
    #expect(security.updateQuery == nil)
    #expect(security.deleteCalls == 0)
  }
  @Test func duplicatesUpdateValueAndACLWithoutDeleting() throws {
    let security = FakeElevenLabsSecurity()
    security.addStatus = errSecDuplicateItem
    try NativeElevenLabsKeychain(security: security).write(Data("replacement".utf8))
    assertFixedNoninteractiveQuery(try #require(security.updateQuery))
    #expect(security.updateAttributes?[kSecAttrAccess as String] as? String == "fake-current-app-only-access")
    #expect(security.updateAttributes?[kSecValueData as String] as? Data == Data("replacement".utf8))
    #expect(security.deleteCalls == 0)
  }
  @Test func missingLoginOrACLAbortsWithoutFallback() {
    let security = FakeElevenLabsSecurity()
    security.openFailure = true
    let keychain = NativeElevenLabsKeychain(security: security)
    #expect(throws: ElevenLabsCredentialError.unavailable) { try keychain.read() }
    #expect(throws: ElevenLabsCredentialError.unavailable) { try keychain.write(Data()) }
    #expect(security.readQuery == nil)
    #expect(security.addCalls == 0)
    security.openFailure = false
    security.accessFailure = true
    #expect(throws: ElevenLabsCredentialError.unavailable) { try keychain.write(Data()) }
    #expect(security.addCalls == 0)
  }
  @Test func deniedReadsNeverBecomeMissingOrRetryInteractively() {
    let security = FakeElevenLabsSecurity()
    security.readStatus = errSecInteractionNotAllowed
    #expect(throws: ElevenLabsCredentialError.accessDenied) {
      try NativeElevenLabsKeychain(security: security).read()
    }
    #expect(security.readCalls == 1)
    #expect(security.addCalls == 0)
  }
  @Test func updateFailureNeverDeletesExistingCredential() {
    let security = FakeElevenLabsSecurity()
    security.addStatus = errSecDuplicateItem
    security.updateStatus = errSecAuthFailed
    #expect(throws: ElevenLabsCredentialError.accessDenied) {
      try NativeElevenLabsKeychain(security: security).write(Data("synthetic".utf8))
    }
    #expect(security.addCalls == 1)
    #expect(security.deleteCalls == 0)
  }
  @Test func explicitRemovalUsesFixedQueryAndMissingIsIdempotent() throws {
    let security = FakeElevenLabsSecurity()
    security.deleteStatus = errSecItemNotFound
    try NativeElevenLabsKeychain(security: security).remove()
    assertFixedNoninteractiveQuery(try #require(security.deleteQuery))
    #expect(security.deleteCalls == 1)
  }
  @Test func malformedResultIsSanitized() {
    let security = FakeElevenLabsSecurity()
    security.readStatus = errSecSuccess
    security.readResult = "wrong-type" as CFString
    #expect(throws: ElevenLabsCredentialError.invalidStoredValue) {
      try NativeElevenLabsKeychain(security: security).read()
    }
  }
  private func assertFixedNoninteractiveQuery(_ query: [String: Any]) {
    #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
    #expect(query[kSecAttrService as String] as? String == "com.argus.development.elevenlabs")
    #expect(query[kSecAttrAccount as String] as? String == "voice-api-key")
    #expect(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String)
    #expect(query[kSecUseDataProtectionKeychain as String] == nil)
    #expect(query[kSecAttrAccessGroup as String] == nil)
    #expect(query[kSecAttrSynchronizable as String] == nil)
  }
}

@MainActor private final class FakeElevenLabsSecurity: ElevenLabsSecurityAPI {
  var openFailure = false
  var accessFailure = false
  var accessCalls = 0
  var readCalls = 0
  var addCalls = 0
  var deleteCalls = 0
  var readStatus = errSecItemNotFound
  var addStatus = errSecSuccess
  var updateStatus = errSecSuccess
  var deleteStatus = errSecSuccess
  var readResult: CFTypeRef?
  var readQuery: [String: Any]?
  var addQuery: [String: Any]?
  var updateQuery: [String: Any]?
  var updateAttributes: [String: Any]?
  var deleteQuery: [String: Any]?
  func openLoginKeychain() throws -> CFTypeRef {
    if openFailure { throw ElevenLabsCredentialError.unavailable }
    return "fake-login-handle" as CFString
  }
  func currentApplicationOnlyAccess() throws -> CFTypeRef {
    accessCalls += 1
    if accessFailure { throw ElevenLabsCredentialError.unavailable }
    return "fake-current-app-only-access" as CFString
  }
  func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
    readCalls += 1; readQuery = query; return (readStatus, readResult)
  }
  func add(_ attributes: [String: Any]) -> OSStatus {
    addCalls += 1; addQuery = attributes; return addStatus
  }
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    updateQuery = query; updateAttributes = attributes; return updateStatus
  }
  func delete(_ query: [String: Any]) -> OSStatus {
    deleteCalls += 1; deleteQuery = query; return deleteStatus
  }
}
