import Foundation
import Observation
import ArgusCore
import ArgusPlatform

public enum VoiceSuspensionReason: Hashable, Sendable {
  case systemSleep, displaySleep, screenLock, sessionInactive, startupUnverified
}

/// Persisted consent is independent of transient capture and lifecycle suspension.
@MainActor @Observable public final class VoiceExperienceController {
  public private(set) var alwaysListen: Bool
  public private(set) var spokenResponses: Bool
  public private(set) var isSpeaking = false
  public var statusText: String {
    if isSpeaking { return "Speaking with ElevenLabs" }
    if let speechFailure { return speechFailure.presentationMessage }
    if suspensions.contains(.startupUnverified) {
      return alwaysListen ? "Waiting for unlock or explicit Start listening" : activation.statusText
    }
    if !suspensions.isEmpty { return "Listening suspended" }
    if let message { return message }
    return activation.statusText
  }
  /// Loading remembered mode is deliberately explicit. Initialization never changes current mode.
  public var preferredMode: ActivationMode? { preferences.preferredMode }

  private let activation: ActivationController
  private let speech: any SpeechOutput
  private let permissions: any ActivationPermissionChecking
  private let preferences: VoicePreferences
  private var suspensions: Set<VoiceSuspensionReason> = []
  private var generation: UInt64 = 0
  private var requestID: UUID?
  private var resumeAfterSpeech = false
  private var pausedActivationGeneration: UInt64 = 0
  private var pausedMode: ActivationMode = .clap
  private var cooldown: Task<Void, Never>?
  private var message: String?
  private var speechFailure: ElevenLabsSpeechFailure?

  public init(activation: ActivationController, speech: any SpeechOutput,
    defaults: UserDefaults = .standard,
    permissions: any ActivationPermissionChecking = NativeActivationPermissionChecker()) {
    self.activation = activation
    self.speech = speech
    self.permissions = permissions
    preferences = VoicePreferences(defaults: defaults)
    alwaysListen = preferences.alwaysListen
    spokenResponses = preferences.spokenResponses
    speech.onCompletion = { [weak self] id, result in self?.completed(id, result: result) }
  }

  /// UI entry points record intent synchronously, before queued work can race Stop or lock.
  public func requestAlwaysListen(_ enabled: Bool) {
    prepareAlwaysListen(enabled)
    if enabled { queueCapture(automatic: false) }
  }

  public func requestEnableOnce() {
    prepareExplicitStart()
    queueCapture(automatic: false)
  }

  public func requestResume(reason: VoiceSuspensionReason) {
    suspensions.remove(reason)
    if alwaysListen { queueCapture(automatic: true) }
  }

  public func setAlwaysListen(_ enabled: Bool) async {
    prepareAlwaysListen(enabled)
    if enabled { await startCapture(automatic: false) }
  }

  /// Explicit legacy one-session activation does not change remembered always-listen consent.
  public func enableOnce() async {
    prepareExplicitStart()
    await startCapture(automatic: false)
  }

  private func prepareAlwaysListen(_ enabled: Bool) {
    alwaysListen = enabled
    preferences.alwaysListen = enabled
    if enabled { prepareExplicitStart() } else { stopListening() }
  }

  private func prepareExplicitStart() {
    suspensions.remove(.startupUnverified)
    invalidateSpeech()
  }

  private func queueCapture(automatic: Bool, oneShot: Bool = false) {
    let token = generation
    let captureToken = activation.intentGeneration
    Task { @MainActor [weak self] in
      guard let self, self.generation == token,
        self.activation.intentGeneration == captureToken else { return }
      await self.startCapture(automatic: automatic, oneShot: oneShot)
    }
  }

  public func setSpokenResponses(_ enabled: Bool) {
    spokenResponses = enabled
    preferences.spokenResponses = enabled
    if !enabled {
      let shouldResume = canRestorePausedCapture
      invalidateSpeech()
      if shouldResume { queueCapture(automatic: true, oneShot: true) }
    }
  }

  public func stopListening() {
    alwaysListen = false
    preferences.alwaysListen = false
    invalidateSpeech()
    activation.stop()
    message = nil
  }

  /// Credential changes/revocation cancel synchronously without restoring paused capture.
  /// Remembered listening intent is retained, but late speech callbacks cannot restart it.
  public func speechAuthorizationChanged() {
    invalidateSpeech()
    // Also invalidate a capture restore that already passed the cooldown and is awaiting start.
    activation.stop()
    message = "ElevenLabs voice settings changed. Start listening to continue."
  }

  public func reportSpeechFailure(_ id: UUID, failure: ElevenLabsSpeechFailure) {
    guard requestID == id else { return }
    speechFailure = failure
  }

  public func suspend(reason: VoiceSuspensionReason) {
    suspensions.insert(reason)
    invalidateSpeech()
    activation.stop()
  }

  public func resume(reason: VoiceSuspensionReason) async {
    suspensions.remove(reason)
    await restoreIfEnabled()
  }

  public func restoreIfEnabled() async {
    guard alwaysListen else { return }
    await startCapture(automatic: true)
  }

  public func setMode(_ mode: ActivationMode) async {
    invalidateSpeech()
    activation.stop()
    activation.mode = mode
    preferences.preferredMode = mode
    await restoreIfEnabled()
  }

  public func handleActivation(_ trigger: ActivationTrigger) {
    guard activation.isListening, spokenResponses, !isSpeaking, cooldown == nil,
      suspensions.isEmpty else { return }
    speak("I'm here.")
  }

  /// A fixed sample sent only with provider consent. Preview cannot authorize capture.
  public func previewSpeech() {
    guard spokenResponses, suspensions.subtracting([.startupUnverified]).isEmpty else { return }
    speak("I'm Argus. I'm here when you need me.")
  }

  private func startCapture(automatic: Bool, oneShot: Bool = false) async {
    let token = generation
    await activation.waitForPendingStart()
    guard token == generation, suspensions.isEmpty, !isSpeaking, cooldown == nil else { return }
    if automatic {
      guard alwaysListen || oneShot else { return }
      guard permissions.isAuthorized(for: activation.mode) else {
        message = "Enable listening to review microphone and speech permissions."
        return
      }
    }
    message = nil
    speechFailure = nil
    if automatic { await activation.enableIfAuthorized() }
    else { await activation.enable() }
  }

  private func speak(_ text: String) {
    // A superseding preview retains only the same still-valid paused capture intent.
    let shouldResume = activation.isListening || canRestorePausedCapture
    invalidateSpeech()
    activation.stop()
    pausedActivationGeneration = activation.intentGeneration
    pausedMode = activation.mode
    resumeAfterSpeech = shouldResume
    isSpeaking = true
    message = nil
    requestID = speech.speak(text)
  }

  private var canRestorePausedCapture: Bool {
    resumeAfterSpeech && pausedActivationGeneration == activation.intentGeneration
      && pausedMode == activation.mode && suspensions.isEmpty
  }

  private func completed(_ id: UUID, result: SpeechOutputResult) {
    guard requestID == id else { return }
    requestID = nil
    isSpeaking = false
    guard result == .finished else {
      resumeAfterSpeech = false
      message = result == .failed
        ? (message ?? "ElevenLabs speech unavailable. Start listening to try again.") : nil
      return
    }
    let shouldResume = resumeAfterSpeech
    let token = generation
    let captureToken = pausedActivationGeneration
    let mode = pausedMode
    cooldown = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
      guard let self, self.generation == token else { return }
      self.cooldown = nil
      self.resumeAfterSpeech = false
      guard shouldResume, self.spokenResponses, self.suspensions.isEmpty,
        self.activation.intentGeneration == captureToken, self.activation.mode == mode else { return }
      await self.startCapture(automatic: true, oneShot: true)
    }
  }

  private func invalidateSpeech() {
    generation &+= 1
    cooldown?.cancel()
    cooldown = nil
    requestID = nil
    resumeAfterSpeech = false
    isSpeaking = false
    speechFailure = nil
    speech.stop()
  }
}
