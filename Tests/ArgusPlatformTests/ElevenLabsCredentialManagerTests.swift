import Foundation
import Testing
@testable import ArgusPlatform

@Suite @MainActor
struct ElevenLabsCredentialManagerTests {
  @Test func constructionDoesNotTouchKeychainAndMissingRemainsMissing() throws {
    let boundary = FakeElevenLabsKeychain()
    let manager = ElevenLabsCredentialManager(keychain: boundary)
    #expect(boundary.reads == 0)
    #expect(try manager.apiKey() == nil)
    #expect(boundary.reads == 1)
    #expect(boundary.writes == 0)
    #expect(boundary.deletes == 0)
  }
  @Test func explicitSaveLoadRemoveUseOnlyBoundary() throws {
    let boundary = FakeElevenLabsKeychain()
    let manager = ElevenLabsCredentialManager(keychain: boundary)
    try manager.save("synthetic-test-value")
    #expect(try manager.load() == "synthetic-test-value")
    try manager.remove()
    #expect(try manager.load() == nil)
    #expect(boundary.writes == 1)
    #expect(boundary.deletes == 1)
  }
  @Test func invalidInputsNeverWrite() {
    let boundary = FakeElevenLabsKeychain()
    let manager = ElevenLabsCredentialManager(keychain: boundary)
    for value in ["", "with space", "bad\nvalue", "é", String(repeating: "x", count: 513)] {
      #expect(throws: ElevenLabsCredentialError.invalidInput) { try manager.save(value) }
    }
    #expect(boundary.writes == 0)
  }
  @Test func failuresDoNotDeleteOrFallback() {
    let boundary = FakeElevenLabsKeychain()
    boundary.failure = .unavailable
    let manager = ElevenLabsCredentialManager(keychain: boundary)
    #expect(throws: ElevenLabsCredentialError.unavailable) { try manager.load() }
    #expect(throws: ElevenLabsCredentialError.unavailable) { try manager.save("synthetic") }
    #expect(boundary.deletes == 0)
  }
  @Test func corruptStoredValueFailsClosed() {
    let boundary = FakeElevenLabsKeychain()
    boundary.data = Data([0xff])
    let manager = ElevenLabsCredentialManager(keychain: boundary)
    #expect(throws: ElevenLabsCredentialError.invalidStoredValue) { try manager.apiKey() }
    boundary.data = Data("bad\nvalue".utf8)
    #expect(throws: ElevenLabsCredentialError.invalidStoredValue) { try manager.apiKey() }
    #expect(boundary.deletes == 0)
  }
}

@MainActor private final class FakeElevenLabsKeychain: ElevenLabsKeychainBoundary {
  var data: Data?
  var failure: ElevenLabsCredentialError?
  var reads = 0
  var writes = 0
  var deletes = 0
  func read() throws -> Data? { reads += 1; if let failure { throw failure }; return data }
  func write(_ data: Data) throws { writes += 1; if let failure { throw failure }; self.data = data }
  func remove() throws { deletes += 1; if let failure { throw failure }; data = nil }
}
