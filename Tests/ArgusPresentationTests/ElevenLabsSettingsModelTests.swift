import ArgusPlatform
import Foundation
import Testing
@testable import ArgusPresentation

@Suite @MainActor struct ElevenLabsSettingsModelTests {
  @Test func initializationDoesNotReadCredentialsOrOptIn() {
    let credentials = SettingsFakeCredentials()
    let defaults = UserDefaults(suiteName: "ElevenLabsSettingsTests.\(UUID())")!
    let model = ElevenLabsSettingsModel(credentials: credentials, defaults: defaults)
    #expect(credentials.reads == 0)
    #expect(model.status == .unchecked)
    #expect(!model.transmissionConsent)
  }
  @Test func refreshDistinguishesMissingConfiguredAndUnavailable() {
    let credentials = SettingsFakeCredentials()
    let model = ElevenLabsSettingsModel(credentials: credentials,
      defaults: UserDefaults(suiteName: "ElevenLabsSettingsTests.\(UUID())")!)
    model.refresh()
    #expect(model.status == .notConfigured)
    credentials.key = "synthetic"
    model.refresh()
    #expect(model.status == .configured)
    credentials.failure = .accessDenied
    model.refresh()
    #expect(model.status == .unavailable)
    #expect(model.errorMessage != nil)
    #expect(credentials.removals == 0)
  }
  @Test func explicitSaveAndRemoveNeverPersistKeyInDefaults() {
    let credentials = SettingsFakeCredentials()
    let name = "ElevenLabsSettingsTests.\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let model = ElevenLabsSettingsModel(credentials: credentials, defaults: defaults)
    model.save("synthetic")
    #expect(model.status == .configured)
    #expect((defaults.persistentDomain(forName: name) ?? [:]).isEmpty)
    model.setTransmissionConsent(true)
    #expect(model.transmissionConsent)
    #expect(defaults.persistentDomain(forName: name)?.count == 1)
    model.remove()
    #expect(model.status == .notConfigured)
    #expect(credentials.removals == 1)
  }
  @Test func invalidSaveIsNotReportedAsConfigured() {
    let credentials = SettingsFakeCredentials()
    credentials.failure = .invalidInput
    let model = ElevenLabsSettingsModel(credentials: credentials,
      defaults: UserDefaults(suiteName: "ElevenLabsSettingsTests.\(UUID())")!)
    model.save("")
    #expect(model.status == .error)
    #expect(model.errorMessage != nil)
    #expect(credentials.removals == 0)
  }

  @Test func setupIssueGuidesMissingKeyAndConsent() throws {
    let credentials = SettingsFakeCredentials()
    let model = ElevenLabsSettingsModel(credentials: credentials,
      defaults: UserDefaults(suiteName: "ElevenLabsSettingsTests.\(UUID())")!)
    model.refresh()
    var issue = try #require(model.setupIssue)
    #expect(issue.title == "ElevenLabs voice is not ready")
    #expect(issue.primaryAction == "Save an API key")
    credentials.key = "synthetic"
    model.refresh()
    issue = try #require(model.setupIssue)
    #expect(issue.message.contains("text-transmission consent"))
    #expect(issue.primaryAction == "Allow text transmission")
    model.setTransmissionConsent(true)
    #expect(model.setupIssue == nil)
  }
}

@MainActor private final class SettingsFakeCredentials: ElevenLabsCredentialManaging {
  var key: String?
  var failure: ElevenLabsCredentialError?
  var reads = 0
  var removals = 0
  func apiKey() throws -> String? { try load() }
  func load() throws -> String? { reads += 1; if let failure { throw failure }; return key }
  func save(_ key: String) throws { if let failure { throw failure }; self.key = key }
  func remove() throws { if let failure { throw failure }; removals += 1; key = nil }
}
