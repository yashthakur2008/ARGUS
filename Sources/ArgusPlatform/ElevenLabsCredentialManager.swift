import Foundation

public enum ElevenLabsCredentialError: Error, Equatable, Sendable {
  case unavailable, accessDenied, operationFailed, invalidInput, invalidStoredValue
}

@MainActor public protocol ElevenLabsCredentialManaging: ElevenLabsCredentialProvider {
  func save(_ key: String) throws
  func load() throws -> String?
  func remove() throws
}

/// Login-Keychain storage for this development app, not a signed isolated broker.
/// No key is cached. Save/remove must only be invoked by explicit settings actions.
@MainActor public final class ElevenLabsCredentialManager: ElevenLabsCredentialManaging {
  private let keychain: any ElevenLabsKeychainBoundary

  public convenience init() { self.init(keychain: NativeElevenLabsKeychain()) }
  init(keychain: any ElevenLabsKeychainBoundary) { self.keychain = keychain }

  public func apiKey() throws -> String? { try load() }
  public func load() throws -> String? {
    guard let data = try keychain.read() else { return nil }
    guard let key = String(data: data, encoding: .utf8), Self.valid(key) else {
      throw ElevenLabsCredentialError.invalidStoredValue
    }
    return key
  }
  public func save(_ key: String) throws {
    guard Self.valid(key) else { throw ElevenLabsCredentialError.invalidInput }
    try keychain.write(Data(key.utf8))
  }
  public func remove() throws { try keychain.remove() }

  private static func valid(_ key: String) -> Bool {
    !key.isEmpty && key.utf8.count <= 512
      && key.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
  }
}

@MainActor protocol ElevenLabsKeychainBoundary {
  func read() throws -> Data?
  func write(_ data: Data) throws
  func remove() throws
}
