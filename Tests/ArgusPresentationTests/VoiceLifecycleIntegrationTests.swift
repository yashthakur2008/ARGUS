import AppKit
import Foundation
import Testing
import ArgusCore
import ArgusPlatform
@testable import ArgusPresentation

@MainActor struct VoiceLifecycleIntegrationTests {
  @Test func rememberedListeningWaitsForUnlockAndMuteSurvivesEveryResume() async throws {
    let suite = "ARGUS.VoiceLifecycleIntegration.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let audio = LifecycleAudioFixture()
    let activation = ActivationController(service: audio) { _ in }
    let voice = VoiceExperienceController(activation: activation, speech: LifecycleSpeechFixture(),
      defaults: defaults, permissions: LifecyclePermissionFixture())
    await voice.setAlwaysListen(true)
    #expect(audio.explicitStarts == 1)
    let workspace = NotificationCenter(), locks = NotificationCenter()
    let bridge = VoiceLifecycleBridge(workspaceCenter: workspace, lockCenter: locks,
      onSuspend: { voice.suspend(reason: $0) }, onResume: { await voice.resume(reason: $0) })
    defer { bridge.stop() }
    await voice.restoreIfEnabled()
    #expect(voice.alwaysListen)
    #expect(!activation.isListening)
    #expect(audio.automaticStarts == 0)
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    await drain()
    #expect(audio.automaticStarts == 0)
    locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    await drain()
    #expect(audio.automaticStarts == 1)
    #expect(activation.isListening)
    voice.stopListening()
    locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    await drain()
    #expect(!voice.alwaysListen)
    #expect(!activation.isListening)
    #expect(audio.automaticStarts == 1)
    #expect(audio.explicitStarts == 1)
  }

  private func drain() async { for _ in 0..<100 { await Task.yield() } }
}

@MainActor private final class LifecycleAudioFixture: AudioActivationService {
  var state: AudioActivationState = .stopped
  var onActivation: (@MainActor @Sendable (ActivationTrigger) -> Void)?
  var onStateChange: (@MainActor @Sendable (AudioActivationState) -> Void)?
  var explicitStarts = 0
  var automaticStarts = 0
  func start(mode: ActivationMode) async {
    explicitStarts += 1
    state = .listening(mode)
    onStateChange?(state)
  }
  func startIfAuthorized(mode: ActivationMode) async {
    automaticStarts += 1
    state = .listening(mode)
    onStateChange?(state)
  }
  func stop() { state = .stopped; onStateChange?(state) }
}

@MainActor private final class LifecycleSpeechFixture: SpeechOutput {
  var isSpeaking = false
  var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?
  func speak(_ text: String) -> UUID { UUID() }
  func stop() {}
}

@MainActor private struct LifecyclePermissionFixture: ActivationPermissionChecking {
  func isAuthorized(for mode: ActivationMode) -> Bool { true }
}
