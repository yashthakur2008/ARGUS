import ArgusCore
import ArgusPlatform
import Foundation
import Testing
@testable import ArgusPresentation

@Suite @MainActor struct ElevenLabsVoiceIntegrationTests {
  @Test func authorizationChangesCancelPendingAndPlayingSpeech() async throws {
    // A missing pre-mutation cancellation hook lets late responses play and resume capture.
    for change in 0..<3 {
      for alreadyPlaying in [false, true] {
        let h = ElevenVoiceHarness()
        defer { h.cleanUp() }
        await h.voice.setAlwaysListen(true)
        h.voice.setSpokenResponses(true)
        h.voice.handleActivation(.clap)
        let requestID = try #require(h.transport.completions.first)
        if alreadyPlaying { requestID(.success(Data([1]))) }
        h.credentials.beforeMutation = {
          #expect(!h.voice.isSpeaking)
          #expect(!h.playback.playing)
        }
        switch change {
        case 0: h.settings.setTransmissionConsent(false)
        case 1: h.settings.remove()
        default: h.settings.save("synthetic-replacement")
        }
        #expect(!h.voice.isSpeaking)
        #expect(!h.playback.playing)
        let plays = h.playback.plays
        requestID(.success(Data([2])))
        if let id = h.playback.lastID { h.playback.onCompletion?(id, .finished) }
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(250))
        #expect(h.playback.plays == plays)
        #expect(!h.activation.isListening)
        #expect(h.audio.starts == 1)
        #expect(h.voice.alwaysListen)
      }
    }
  }

  @Test func failureShowsProviderContextWithoutRawError() async {
    let h = ElevenVoiceHarness()
    defer { h.cleanUp() }
    h.voice.setSpokenResponses(true)
    h.settings.setTransmissionConsent(false)
    h.voice.previewSpeech()
    for _ in 0..<20 { await Task.yield() }
    #expect(h.voice.statusText.contains("ElevenLabs"))
    #expect(h.voice.statusText.lowercased().contains("consent"))
    #expect(!h.voice.isSpeaking)
    #expect(h.transport.completions.isEmpty)
  }

  @Test func authorizationChangeInvalidatesAlreadyStartedCaptureRestore() async throws {
    for change in 0..<3 {
      let h = ElevenVoiceHarness()
      defer { h.cleanUp() }
      await h.voice.setAlwaysListen(true)
      h.voice.setSpokenResponses(true)
      h.voice.handleActivation(.clap)
      h.transport.completions[0](.success(Data([1])))
      let id = try #require(h.playback.lastID)
      h.audio.hold = true
      h.playback.onCompletion?(id, .finished)
      for _ in 0..<20 { await Task.yield() }
      try await Task.sleep(for: .milliseconds(250))
      for _ in 0..<100 { if h.audio.pending != nil { break }; await Task.yield() }
      try #require(h.audio.pending != nil)
      switch change {
      case 0: h.settings.setTransmissionConsent(false)
      case 1: h.settings.remove()
      default: h.settings.save("synthetic-replacement")
      }
      h.audio.finish()
      for _ in 0..<100 { await Task.yield() }
      #expect(!h.activation.isListening)
      #expect(h.audio.state == .stopped)
      #expect(h.voice.alwaysListen)
    }
  }

  @Test func providerFailureIsVisibleWithoutRemovingStartupCaptureBarrier() async {
    for missingKey in [false, true] {
      let h = ElevenVoiceHarness()
      defer { h.cleanUp() }
      await h.voice.setAlwaysListen(true)
      h.voice.suspend(reason: .startupUnverified)
      h.voice.setSpokenResponses(true)
      if missingKey { h.credentials.key = nil }
      else { h.settings.setTransmissionConsent(false) }
      h.voice.previewSpeech()
      for _ in 0..<30 { await Task.yield() }
      #expect(h.voice.statusText.contains("ElevenLabs"))
      #expect(h.voice.statusText.contains(missingKey ? "Keychain" : "consent"))
      await h.voice.restoreIfEnabled()
      #expect(!h.activation.isListening)
      #expect(h.audio.starts == 1)
    }
  }

  @Test func failedCredentialMutationStillCancelsBeforeSecureStoreCall() {
    for removing in [false, true] {
      let h = ElevenVoiceHarness()
      defer { h.cleanUp() }
      h.voice.setSpokenResponses(true)
      h.voice.previewSpeech()
      h.credentials.failure = .accessDenied
      h.credentials.beforeMutation = { #expect(!h.voice.isSpeaking) }
      if removing { h.settings.remove() } else { h.settings.save("synthetic") }
      h.transport.completions[0](.success(Data([1])))
      #expect(!h.voice.isSpeaking)
      #expect(h.playback.plays == 0)
      #expect(h.settings.status == .unavailable)
    }
  }

  @Test func typedFailureBelongsOnlyToCurrentUtterance() async {
    let h = ElevenVoiceHarness()
    defer { h.cleanUp() }
    h.voice.setSpokenResponses(true)
    h.voice.previewSpeech()
    h.voice.previewSpeech()
    h.transport.completions[0](.failure(.httpStatus(401)))
    for _ in 0..<20 { await Task.yield() }
    #expect(h.voice.isSpeaking)
    #expect(h.voice.statusText == "Speaking with ElevenLabs")
    h.transport.completions[1](.failure(.httpStatus(429)))
    for _ in 0..<20 { await Task.yield() }
    #expect(h.voice.statusText.contains("usage limit"))
    h.settings.remove()
    h.transport.completions[1](.failure(.httpStatus(401)))
    for _ in 0..<20 { await Task.yield() }
    #expect(!h.voice.statusText.contains("denied"))
    #expect(!h.voice.isSpeaking)
  }
}

@MainActor private final class ElevenVoiceHarness {
  let credentials = IntegrationCredentials()
  let transport = IntegrationTransport()
  let playback = IntegrationPlayback()
  let audio = IntegrationAudio()
  let settings: ElevenLabsSettingsModel
  let speech: ElevenLabsSpeechOutput
  let activation: ActivationController
  let voice: VoiceExperienceController
  let defaults: UserDefaults
  let suite = "ElevenVoiceIntegration.\(UUID())"
  init() {
    defaults = UserDefaults(suiteName: suite)!
    settings = ElevenLabsSettingsModel(credentials: credentials, defaults: defaults)
    settings.setTransmissionConsent(true)
    let settings = settings
    speech = ElevenLabsSpeechOutput(credentials: credentials,
      disclosureAccepted: { settings.transmissionConsent }, transport: transport, playback: playback)
    activation = ActivationController(service: audio) { _ in }
    voice = VoiceExperienceController(activation: activation, speech: speech,
      defaults: defaults, permissions: IntegrationPermissions())
    settings.connectSpeech(speech, controller: voice)
  }
  func cleanUp() {
    credentials.beforeMutation = nil
    voice.stopListening()
    audio.finish()
    defaults.removePersistentDomain(forName: suite)
  }
}

@MainActor private final class IntegrationCredentials: ElevenLabsCredentialManaging {
  var beforeMutation: (() -> Void)?
  var key: String? = "synthetic-integration-key"
  var failure: ElevenLabsCredentialError?
  func apiKey() throws -> String? { key }
  func load() throws -> String? { key }
  func save(_ key: String) throws {
    beforeMutation?()
    if let failure { throw failure }
    self.key = key
  }
  func remove() throws {
    beforeMutation?()
    if let failure { throw failure }
    key = nil
  }
}
@MainActor private final class IntegrationCancellation: ElevenLabsRequestCancelling {
  func cancel() {}
}
@MainActor private final class IntegrationTransport: ElevenLabsSpeechTransport {
  var completions: [@MainActor @Sendable (Result<Data, ElevenLabsSpeechFailure>) -> Void] = []
  func send(_ request: URLRequest,
    completion: @escaping @MainActor @Sendable (Result<Data, ElevenLabsSpeechFailure>) -> Void
  ) -> any ElevenLabsRequestCancelling {
    completions.append(completion)
    return IntegrationCancellation()
  }
}
@MainActor private final class IntegrationPlayback: MP3Playback {
  var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?
  var playing = false
  var plays = 0
  var lastID: UUID?
  func play(_ data: Data, id: UUID) throws { playing = true; plays += 1; lastID = id }
  func stop() { playing = false }
}
@MainActor private final class IntegrationPermissions: ActivationPermissionChecking {
  func isAuthorized(for mode: ActivationMode) -> Bool { true }
}
@MainActor private final class IntegrationAudio: AudioActivationService {
  var state: AudioActivationState = .stopped
  var onActivation: (@MainActor @Sendable (ActivationTrigger) -> Void)?
  var onStateChange: (@MainActor @Sendable (AudioActivationState) -> Void)?
  var starts = 0
  var hold = false
  var pending: CheckedContinuation<Void, Never>?
  func start(mode: ActivationMode) async {
    starts += 1
    if hold { await withCheckedContinuation { pending = $0 } }
    state = .listening(mode)
    onStateChange?(state)
  }
  func finish() { hold = false; pending?.resume(); pending = nil }
  func startIfAuthorized(mode: ActivationMode) async { await start(mode: mode) }
  func stop() { state = .stopped; onStateChange?(state) }
}
