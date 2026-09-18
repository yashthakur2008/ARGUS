import ArgusPlatform
import Foundation
import Observation

public enum ElevenLabsCredentialStatus: Equatable, Sendable {
  case unchecked, notConfigured, configured, unavailable, error
}

/// Holds only presentation state and consent, never an API key.
@MainActor @Observable public final class ElevenLabsSettingsModel {
  public private(set) var status: ElevenLabsCredentialStatus = .unchecked
  public private(set) var errorMessage: String?
  public private(set) var transmissionConsent: Bool
  public let voiceID = ElevenLabsSpeechOutput.voiceID
  @ObservationIgnored private var cancelSpeech: (@MainActor () -> Void)?
  @ObservationIgnored private let credentials: any ElevenLabsCredentialManaging
  @ObservationIgnored private let defaults: UserDefaults
  private static let consentKey = "voice.elevenLabsTransmissionConsent"

  public init(credentials: any ElevenLabsCredentialManaging, defaults: UserDefaults = .standard) {
    self.credentials = credentials
    self.defaults = defaults
    transmissionConsent = defaults.bool(forKey: Self.consentKey)
  }

  public var statusText: String {
    switch status {
    case .unchecked: "Credential status has not been checked."
    case .notConfigured: "No ElevenLabs API key is configured."
    case .configured: "API key is available in the login Keychain. Provider access has not been verified."
    case .unavailable: "The login Keychain credential is unavailable. Voice remains silent."
    case .error: "Credential setup failed. Voice availability has not been verified."
    }
  }

  /// Shared by production composition and fake-boundary integration tests.
  /// Weak controller references avoid a settings/speech/controller ownership cycle.
  public func connectSpeech(_ speech: ElevenLabsSpeechOutput, controller: VoiceExperienceController) {
    cancelSpeech = { [weak controller] in controller?.speechAuthorizationChanged() }
    speech.onFailure = { [weak controller] id, failure in
      controller?.reportSpeechFailure(id, failure: failure)
    }
  }

  /// Explicit settings refresh, never an interactive Keychain prompt.
  public func refresh() {
    do {
      status = try credentials.load() == nil ? .notConfigured : .configured
      errorMessage = nil
    } catch { show(error) }
  }

  /// The view owns the transient secure input and must clear it after every attempt.
  public func save(_ key: String) {
    cancelSpeech?()
    do { try credentials.save(key); refresh() } catch { show(error) }
  }
  public func remove() {
    cancelSpeech?()
    do { try credentials.remove(); status = .notConfigured; errorMessage = nil }
    catch { show(error) }
  }
  public func setTransmissionConsent(_ allowed: Bool) {
    transmissionConsent = allowed
    if !allowed { cancelSpeech?() }
    defaults.set(allowed, forKey: Self.consentKey)
  }

  private func show(_ error: Error) {
    switch error as? ElevenLabsCredentialError {
    case .unavailable, .accessDenied:
      status = .unavailable
      errorMessage = "Keychain access is unavailable or denied. Unlock the login Keychain and retry explicitly. Rebuilt development apps may need renewed access."
    case .invalidInput:
      status = .error
      errorMessage = "Enter a nonempty API key of up to 512 printable characters without whitespace."
    case .invalidStoredValue:
      status = .error
      errorMessage = "The stored credential is invalid. Explicitly save a replacement or remove it."
    default:
      status = .error
      errorMessage = "The Keychain operation failed. No alternative storage was used."
    }
  }
}
