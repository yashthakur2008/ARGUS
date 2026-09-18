import AppKit
import Foundation
import Testing
import ArgusCore
import ArgusPlatform
import ArgusPresentation
@testable import ArgusApp

/// Uses the production app lifecycle seam without constructing an App/NSApplication,
/// native audio, permission checker, glow controller, reminder store or Keychain.
@MainActor struct AppLifecycleTests {
  @Test func settingsFirstModeChangeCannotStartBeforeObservedUnlock() async {
    let h = AppLifecycleHarness(alwaysListen: true)
    defer { h.cleanUp() }
    #expect(h.attach())
    #expect(h.audio.starts == 0)
    // Settings can act before TodayView and before any reminder-model connection.
    await h.voice.setMode(.wakeWord)
    await h.voice.restoreIfEnabled()
    #expect(h.audio.starts == 0)
    #expect(!h.activation.isListening)
    #expect(h.voice.statusText.contains("Waiting for unlock"))
    h.locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    await h.drain()
    #expect(h.activation.isListening)
    #expect(h.audio.automaticStarts == 1)
    #expect(h.audio.explicitStarts == 0)
  }

  @Test func settingsFirstExplicitStartIsMonitoredWithoutReminderConnection() async {
    let h = AppLifecycleHarness(alwaysListen: false)
    defer { h.cleanUp() }
    #expect(h.attach())
    h.voice.requestEnableOnce()
    await h.drain()
    #expect(h.activation.isListening)
    #expect(h.audio.explicitStarts == 1)
    h.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    #expect(!h.activation.isListening)
    #expect(h.audio.state == .stopped)
    #expect(h.hideCalls == 2) // Initial startup barrier and synchronous sleep.
    h.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    await h.drain()
    #expect(h.audio.starts == 1) // One-shot intent does not become always-listen.
  }

  @Test func duplicateAttachmentDoesNotResetIntentOrDuplicateObservers() async {
    let h = AppLifecycleHarness(alwaysListen: true)
    defer { h.cleanUp() }
    #expect(h.attach())
    await h.voice.enableOnce()
    #expect(h.activation.isListening)
    #expect(!h.attach())
    #expect(h.activation.isListening)
    #expect(h.hideCalls == 1)
    h.locks.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
    #expect(!h.activation.isListening)
    #expect(h.hideCalls == 2)
    h.locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    await h.drain()
    #expect(h.audio.automaticStarts == 1)
  }

  @Test func quitBeforeAnyWindowConnectionStopsCaptureAndQueuedResumption() async {
    let h = AppLifecycleHarness(alwaysListen: true)
    defer { h.cleanUp() }
    #expect(h.attach())
    await h.voice.enableOnce()
    h.locks.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
    h.locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    // Termination must fence the queued unlock before it is delivered.
    h.lifecycle.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    await h.drain()
    #expect(!h.activation.isListening)
    #expect(h.audio.starts == 1)
    #expect(!h.attach())
    let hidden = h.hideCalls
    h.locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    h.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    await h.drain()
    #expect(h.audio.starts == 1)
    #expect(h.hideCalls == hidden)
  }

  @Test func failedStorageStartupCannotArmFromRememberedIntentOrUnlock() async {
    let h = AppLifecycleHarness(alwaysListen: true)
    defer { h.cleanUp() }
    #expect(!h.attach(startupReady: false))
    #expect(!h.activation.isListening)
    let hidden = h.hideCalls
    h.locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    h.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    await h.drain()
    #expect(h.audio.starts == 0)
    #expect(!h.attach())
    h.voice.requestEnableOnce()
    await h.voice.setMode(.wakeWord)
    await h.drain()
    #expect(h.audio.starts == 0)
    h.locks.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
    h.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    #expect(h.hideCalls == hidden) // No monitor was installed on the failed path.
  }

  @Test func attachmentAfterTerminationCannotRearmLifecycle() async {
    let h = AppLifecycleHarness(alwaysListen: true)
    defer { h.cleanUp() }
    h.lifecycle.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    #expect(!h.attach())
    h.locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    await h.drain()
    #expect(h.audio.starts == 0)
  }
}

@MainActor private final class AppLifecycleHarness {
  let lifecycle = AppLifecycle()
  let workspace = NotificationCenter()
  let locks = NotificationCenter()
  let audio = AppLifecycleAudioFake()
  let activation: ActivationController
  let voice: VoiceExperienceController
  let defaults: UserDefaults
  let suite = "ARGUS.AppLifecycleTests.\(UUID())"
  var hideCalls = 0

  init(alwaysListen: Bool) {
    defaults = UserDefaults(suiteName: suite)!
    defaults.set(alwaysListen, forKey: "voice.alwaysListen")
    activation = ActivationController(service: audio) { _ in }
    voice = VoiceExperienceController(activation: activation, speech: AppLifecycleSpeechFake(),
      defaults: defaults, permissions: AppLifecyclePermissionFake())
  }
  func attach(startupReady: Bool = true) -> Bool {
    lifecycle.connectVoice(voice: voice, startupReady: startupReady, hideGlow: { [weak self] in self?.hideCalls += 1 },
      workspaceCenter: workspace, lockCenter: locks)
  }
  func drain() async { for _ in 0..<100 { await Task.yield() } }
  func cleanUp() {
    lifecycle.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    voice.stopListening()
    defaults.removePersistentDomain(forName: suite)
  }
}

@MainActor private final class AppLifecycleAudioFake: AudioActivationService {
  var state: AudioActivationState = .stopped
  var onActivation: (@MainActor @Sendable (ActivationTrigger) -> Void)?
  var onStateChange: (@MainActor @Sendable (AudioActivationState) -> Void)?
  var explicitStarts = 0
  var automaticStarts = 0
  var starts: Int { explicitStarts + automaticStarts }
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

@MainActor private final class AppLifecycleSpeechFake: SpeechOutput {
  var isSpeaking = false
  var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?
  func speak(_ text: String) -> UUID { UUID() }
  func stop() {}
}

private struct AppLifecyclePermissionFake: ActivationPermissionChecking {
  func isAuthorized(for mode: ActivationMode) -> Bool { true }
}
