import Foundation
import Testing
import ArgusCore
import ArgusPlatform
@testable import ArgusPresentation

@MainActor struct VoiceExperienceControllerTests {
  @Test func startupGateDoesNotImplyCaptureIsArmedWhenOff() {
    let h = VoiceHarness()
    h.voice.suspend(reason: .startupUnverified)
    #expect(h.voice.statusText == "Microphone off")
  }

  @Test func selectingClapWhilePersistentUsesAuthorizedOnlyRestart() async {
    let h = VoiceHarness()
    h.activation.mode = .wakeWord
    await h.voice.setAlwaysListen(true)
    await h.voice.setMode(.clap)
    #expect(h.activation.isListening)
    #expect(h.activation.mode == .clap)
    #expect(h.audio.authorizedStarts == [.clap])
  }

  @Test func disablingSpeechRestoresCurrentPersistentOrOneShotCapture() async {
    for persistent in [false, true] {
      let h = VoiceHarness()
      if persistent { await h.voice.setAlwaysListen(true) } else { await h.voice.enableOnce() }
      h.voice.setSpokenResponses(true)
      h.voice.handleActivation(.clap)
      let old = h.speech.currentID
      h.voice.setSpokenResponses(false)
      await h.settle()
      #expect(h.activation.isListening)
      #expect(h.audio.starts.count == 2)
      #expect(h.voice.alwaysListen == persistent)
      h.speech.complete(old)
      await h.settle()
      #expect(h.audio.starts.count == 2)
    }
  }

  @Test func disablingSpeechThenStopDoesNotResume() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.setSpokenResponses(true)
    h.voice.handleActivation(.clap)
    h.voice.setSpokenResponses(false)
    h.voice.stopListening()
    await h.settle()
    #expect(h.audio.starts.count == 1)
    #expect(!h.activation.isListening)
  }

  @Test func activePreviewStatusIsHonestEvenWithStartupGate() {
    let h = VoiceHarness()
    h.voice.suspend(reason: .startupUnverified)
    h.voice.setSpokenResponses(true)
    h.voice.previewSpeech()
    #expect(h.voice.statusText == "Speaking with ElevenLabs")
  }

  @Test func explicitModePreferenceDoesNotSilentlyChangeCurrentModeOnReopen() async {
    let h = VoiceHarness()
    await h.voice.setMode(.wakeWord)
    #expect(h.activation.mode == .wakeWord)
    let reopened = VoiceHarness(defaults: h.defaults)
    #expect(reopened.voice.preferredMode == .wakeWord)
    #expect(reopened.activation.mode == .clap)
    #expect(reopened.audio.starts.isEmpty)
  }

  @Test func stopDuringCooldownInvalidatesScheduledResume() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.setSpokenResponses(true)
    h.voice.handleActivation(.clap)
    h.speech.complete(h.speech.currentID)
    h.voice.stopListening()
    await h.settle()
    #expect(h.audio.starts.count == 1)
    #expect(!h.activation.isListening)
  }

  @Test func resumeWaitsForOldPermissionCleanupWithoutLosingCurrentIntent() async throws {
    let h = VoiceHarness()
    h.audio.hold = true
    let enabling = Task { await h.voice.setAlwaysListen(true) }
    await h.waitForPermission()
    try #require(h.audio.pending != nil)
    h.voice.suspend(reason: .systemSleep)
    let resuming = Task { await h.voice.resume(reason: .systemSleep) }
    for _ in 0..<10 { await Task.yield() }
    #expect(h.audio.starts.count == 1)
    h.audio.finish()
    await enabling.value
    await resuming.value
    #expect(h.activation.isListening)
    #expect(h.audio.starts.count == 2)
  }

  @Test func queuedEnableCannotUndoLaterSynchronousStop() async {
    for persistent in [false, true] {
      let h = VoiceHarness()
      if persistent { h.voice.requestAlwaysListen(true) } else { h.voice.requestEnableOnce() }
      h.voice.stopListening()
      await h.settle()
      #expect(h.audio.starts.isEmpty)
      #expect(!h.voice.alwaysListen)
    }
  }

  @Test func queuedResumeCannotClearNewerLock() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.suspend(reason: .screenLock)
    h.voice.requestResume(reason: .screenLock)
    h.voice.suspend(reason: .screenLock)
    await h.settle()
    #expect(h.audio.starts.count == 1)
    #expect(!h.activation.isListening)
  }

  @Test func startupUnverifiedBlocksAutomaticButExplicitEnableClearsOnlyUnknown() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.suspend(reason: .startupUnverified)
    await h.voice.restoreIfEnabled()
    #expect(!h.activation.isListening)
    h.voice.suspend(reason: .screenLock)
    await h.voice.enableOnce()
    #expect(!h.activation.isListening)
    await h.voice.resume(reason: .screenLock)
    #expect(h.activation.isListening)
  }

  @Test func previewCannotAuthorizeUnknownStartupCapture() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.suspend(reason: .startupUnverified)
    h.voice.setSpokenResponses(true)
    h.permissions.allowed = false
    h.voice.previewSpeech()
    #expect(h.voice.isSpeaking)
    #expect(h.speech.texts.count == 1)
    h.speech.complete(h.speech.currentID)
    await h.settle()
    #expect(!h.activation.isListening)
    await h.voice.restoreIfEnabled()
    #expect(!h.activation.isListening)
  }

  @Test func defaultsAreOffAndInitializationDoesNotStart() async {
    let h = VoiceHarness()
    #expect(!h.voice.alwaysListen)
    #expect(!h.voice.spokenResponses)
    await h.voice.restoreIfEnabled()
    h.voice.previewSpeech()
    #expect(h.audio.starts.isEmpty)
    #expect(h.speech.texts.isEmpty)
  }

  @Test func rememberedIntentRestoresOnlyAfterExplicitRestore() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.setSpokenResponses(true)
    let reopened = VoiceHarness(defaults: h.defaults)
    #expect(reopened.voice.alwaysListen)
    #expect(reopened.voice.spokenResponses)
    #expect(reopened.audio.starts.isEmpty)
    await reopened.voice.restoreIfEnabled()
    #expect(reopened.activation.isListening)
  }

  @Test func automaticRestoreDeniedDoesNotStartOrRequest() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.suspend(reason: .systemSleep)
    h.permissions.allowed = false
    await h.voice.resume(reason: .systemSleep)
    #expect(h.audio.starts.count == 1)
    #expect(!h.activation.isListening)
    #expect(h.voice.statusText.localizedCaseInsensitiveContains("enable"))
    #expect(h.voice.alwaysListen)
  }

  @Test func deniedAutomaticRestoreHasActionableSettingsIssue() async throws {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.suspend(reason: .systemSleep)
    h.permissions.allowed = false
    await h.voice.resume(reason: .systemSleep)
    let issue = try #require(h.voice.settingsIssue)
    #expect(issue.title == "Microphone and Speech need attention")
    #expect(issue.message.contains("System Settings"))
    #expect(issue.primaryAction == "Review permissions")
  }

  @Test func offDuringPendingPermissionCannotRestart() async throws {
    let h = VoiceHarness()
    h.audio.hold = true
    let enabling = Task { await h.voice.setAlwaysListen(true) }
    await h.waitForPermission()
    try #require(h.audio.pending != nil)
    await h.voice.setAlwaysListen(false)
    h.audio.finish()
    await enabling.value
    #expect(!h.voice.alwaysListen)
    #expect(!h.activation.isListening)
    #expect(h.audio.state == .stopped)
  }

  @Test func suspensionDuringPermissionPreservesIntentButStopsCapture() async throws {
    let h = VoiceHarness()
    h.audio.hold = true
    let enabling = Task { await h.voice.setAlwaysListen(true) }
    await h.waitForPermission()
    try #require(h.audio.pending != nil)
    h.voice.suspend(reason: .screenLock)
    h.audio.finish()
    await enabling.value
    #expect(h.voice.alwaysListen)
    #expect(!h.activation.isListening)
    await h.voice.resume(reason: .screenLock)
    #expect(h.activation.isListening)
  }

  @Test func wakingDoesNotClearLockOrInactiveSession() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.suspend(reason: .systemSleep)
    h.voice.suspend(reason: .screenLock)
    h.voice.suspend(reason: .sessionInactive)
    await h.voice.resume(reason: .systemSleep)
    #expect(!h.activation.isListening)
    await h.voice.resume(reason: .screenLock)
    #expect(!h.activation.isListening)
    await h.voice.resume(reason: .sessionInactive)
    #expect(h.activation.isListening)
  }

  @Test func stopClearsRememberedIntentAndStaleCompletionCannotResume() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.setSpokenResponses(true)
    h.voice.handleActivation(.clap)
    let id = h.speech.currentID
    #expect(h.voice.isSpeaking)
    #expect(!h.activation.isListening)
    h.voice.stopListening()
    h.speech.complete(id)
    await h.settle()
    #expect(!h.voice.alwaysListen)
    #expect(!h.voice.isSpeaking)
    #expect(h.audio.starts.count == 1)
    #expect(!VoiceHarness(defaults: h.defaults).voice.alwaysListen)
  }

  @Test func completionRestoresCaptureAfterCooldownButOnlyOnce() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.setSpokenResponses(true)
    h.voice.handleActivation(.clap)
    h.voice.handleActivation(.clap)
    #expect(h.speech.texts == ["I'm here."])
    #expect(!h.activation.isListening)
    let id = h.speech.currentID
    h.speech.complete(id)
    #expect(!h.activation.isListening)
    await h.settle()
    #expect(h.activation.isListening)
    #expect(h.audio.starts.count == 2)
    h.speech.complete(id)
    await h.settle()
    #expect(h.audio.starts.count == 2)
  }

  @Test func supersededPreviewCompletionDoesNotResumeNewSpeech() async {
    let h = VoiceHarness()
    await h.voice.setAlwaysListen(true)
    h.voice.setSpokenResponses(true)
    h.voice.previewSpeech()
    let old = h.speech.currentID
    h.voice.previewSpeech()
    let current = h.speech.currentID
    #expect(old != current)
    h.speech.complete(old)
    await h.settle()
    #expect(h.voice.isSpeaking)
    #expect(!h.activation.isListening)
    h.speech.complete(current)
    await h.settle()
    #expect(h.activation.isListening)
  }

  @Test func speechOffSuspensionErrorAndModeChangeInvalidateCompletion() async {
    for reason in 0..<4 {
      let h = VoiceHarness()
      await h.voice.setAlwaysListen(true)
      h.voice.setSpokenResponses(true)
      h.voice.handleActivation(.clap)
      let old = h.speech.currentID
      switch reason {
      case 0: h.voice.setSpokenResponses(false)
      case 1: h.voice.suspend(reason: .screenLock)
      case 2: h.speech.complete(old, outcome: .failed)
      default: await h.voice.setMode(.wakeWord)
      }
      await h.settle()
      let count = h.audio.starts.count
      h.speech.complete(old)
      await h.settle()
      #expect(h.audio.starts.count == count)
      #expect(!h.voice.isSpeaking)
    }
  }

  @Test func disabledSpeechDoesNotInterruptLegacyOneShotAndEnabledSpeechRestoresIt() async {
    let h = VoiceHarness()
    await h.activation.enable()
    h.voice.handleActivation(.clap)
    #expect(h.activation.isListening)
    #expect(h.speech.texts.isEmpty)
    h.voice.setSpokenResponses(true)
    h.voice.handleActivation(.clap)
    #expect(!h.activation.isListening)
    h.speech.complete(h.speech.currentID)
    await h.settle()
    #expect(h.activation.isListening)
    #expect(!h.voice.alwaysListen)
  }

  @Test func directLegacyStopOrModeChangeDuringSpeechDoesNotRestartCapture() async {
    for changeMode in [false, true] {
      let h = VoiceHarness()
      await h.activation.enable()
      h.voice.setSpokenResponses(true)
      h.voice.handleActivation(.clap)
      if changeMode { h.activation.mode = .wakeWord } else { h.activation.stop() }
      h.speech.complete(h.speech.currentID)
      await h.settle()
      #expect(h.audio.starts.count == 1)
    }
  }

  @Test func previewWhileOffNeverEnablesCapture() async {
    let h = VoiceHarness()
    h.voice.setSpokenResponses(true)
    h.voice.previewSpeech()
    h.speech.complete(h.speech.currentID)
    await h.settle()
    #expect(h.audio.starts.isEmpty)
  }
}

@MainActor private final class VoiceHarness {
  let defaults: UserDefaults
  let audio = VoiceAudioFake()
  let speech = VoiceSpeechFake()
  let permissions = VoicePermissionFake()
  let activation: ActivationController
  let voice: VoiceExperienceController
  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults ?? UserDefaults(suiteName: "voice-test-\(UUID())")!
    activation = ActivationController(service: audio) { _ in }
    voice = VoiceExperienceController(activation: activation, speech: speech,
      defaults: self.defaults, permissions: permissions)
  }
  func waitForPermission() async {
    for _ in 0..<1_000 { if audio.pending != nil { return }; await Task.yield() }
  }
  func settle() async {
    // Let queued main-actor work install its cooldown before waiting for its deadline.
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(350))
  }
}

@MainActor private final class VoicePermissionFake: ActivationPermissionChecking {
  var allowed = true
  func isAuthorized(for mode: ActivationMode) -> Bool { allowed }
}
@MainActor private final class VoiceSpeechFake: SpeechOutput {
  var isSpeaking = false
  var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?
  var currentID: UUID?
  var texts: [String] = []
  func speak(_ text: String) -> UUID {
    let id = UUID(); currentID = id; texts.append(text); isSpeaking = true; return id
  }
  func stop() { isSpeaking = false }
  func complete(_ id: UUID?, outcome: SpeechOutputResult = .finished) {
    guard let id else { return }
    if id == currentID { isSpeaking = false }
    onCompletion?(id, outcome)
  }
}
@MainActor private final class VoiceAudioFake: AudioActivationService {
  var state: AudioActivationState = .stopped
  var onActivation: (@MainActor @Sendable (ActivationTrigger) -> Void)?
  var onStateChange: (@MainActor @Sendable (AudioActivationState) -> Void)?
  var starts: [ActivationMode] = []
  var authorizedStarts: [ActivationMode] = []
  var hold = false
  var pending: CheckedContinuation<Void, Never>?
  func start(mode: ActivationMode) async {
    starts.append(mode); state = .requestingPermission; onStateChange?(state)
    if hold { await withCheckedContinuation { pending = $0 } }
    state = .listening(mode); onStateChange?(state)
  }
  func startIfAuthorized(mode: ActivationMode) async { authorizedStarts.append(mode); await start(mode: mode) }
  func finish() { hold = false; pending?.resume(); pending = nil }
  func stop() { state = .stopped; onStateChange?(state) }
}
