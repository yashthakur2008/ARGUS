import SwiftUI
import AppKit
import UserNotifications
import ArgusPresentation
import ArgusStore
import ArgusPlatform

@main
struct ArgusApplication: App {
  @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
  private let model: AppModel?
  private let startupError: String?
  private let appearance: AppearanceSettings
  private let activation: ActivationController
  private let glow: ScreenEdgeGlowController
  private let voice: VoiceExperienceController
  private let elevenLabs: ElevenLabsSettingsModel
  private let login: LoginItemController

  init() {
    let preferences: UserDefaults
    if let suite = ProcessInfo.processInfo.environment["ARGUS_PREFERENCES_SUITE"], !suite.isEmpty,
      let isolated = UserDefaults(suiteName: suite) {
      preferences = isolated
    } else { preferences = .standard }
    let appearance = AppearanceSettings(defaults: preferences)
    let glow = ScreenEdgeGlowController()
    self.appearance = appearance
    self.glow = glow
    let feedback = VoiceFeedbackRelay()
    let activation = ActivationController(service: LocalAudioActivationService()) { trigger in
      glow.show(color: appearance.nsColor, reduceMotion: appearance.reduceMotion)
      if let trigger { feedback.voice?.handleActivation(trigger) }
    }
    self.activation = activation
    let credentials = ElevenLabsCredentialManager()
    let elevenLabs = ElevenLabsSettingsModel(credentials: credentials, defaults: preferences)
    let speech = ElevenLabsSpeechOutput(credentials: credentials,
      disclosureAccepted: { elevenLabs.transmissionConsent })
    let voice = VoiceExperienceController(activation: activation, speech: speech,
      defaults: preferences, permissions: NativeActivationPermissionChecker())
    elevenLabs.connectSpeech(speech, controller: voice)
    self.elevenLabs = elevenLabs
    if let preferredMode = voice.preferredMode { activation.mode = preferredMode }
    self.voice = voice
    self.login = LoginItemController(service: NativeLoginItemService())
    feedback.voice = voice
    do {
      guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else {
        throw AppStartupError.bundledAppRequired
      }
      let directory: URL
      let directoryAttributes: [FileAttributeKey: Any]?
      if let override = ProcessInfo.processInfo.environment["ARGUS_DATA_DIR"], !override.isEmpty {
        directory = URL(fileURLWithPath: override, isDirectory: true)
        directoryAttributes = nil
      } else {
        directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
          appropriateFor: nil, create: true).appendingPathComponent("ARGUS", isDirectory: true)
        directoryAttributes = [.posixPermissions: 0o700]
      }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: directoryAttributes)
      let store = try ReminderStore(databaseURL: directory.appendingPathComponent("reminders.sqlite"))
      let client = UserNotificationClient(center: UNUserNotificationCenter.current(), clock: { Date() })
      model = AppModel(store: store, client: client, clock: { Date() },
        requestPermission: { try await client.requestAuthorization() })
      startupError = nil
    } catch {
      model = nil
      startupError = "ARGUS could not start. Use the development .app bundle, and verify its local data directory is accessible. Existing data was not replaced. \(error)"
    }
  }

  var body: some Scene {
    WindowGroup("ARGUS", id: "argus-main") {
      Group {
        if let model {
          TodayView(model: model, activation: activation, appearance: appearance, voice: voice, login: login,
            elevenLabs: elevenLabs)
            .task {
              if lifecycle.connect(model, voice: voice, glow: glow) {
                await voice.restoreIfEnabled()
              }
              await model.refresh()
            }
            .onChange(of: appearance.reduceMotion) { _, value in glow.setReduceMotion(value) }
        } else {
          ContentUnavailableView("Local storage unavailable", systemImage: "externaldrive.badge.exclamationmark",
            description: Text(startupError ?? "Unknown storage error"))
            .padding(40).frame(minWidth: 600, minHeight: 300)
        }
      }
    }.defaultSize(width: 1040, height: 740)
    Settings {
      if let model {
        SettingsView(model: model, activation: activation, appearance: appearance, voice: voice, login: login,
          elevenLabs: elevenLabs)
          .onChange(of: appearance.reduceMotion) { _, value in glow.setReduceMotion(value) }
      }
    }
    MenuBarExtra("ARGUS", systemImage: voice.isSpeaking ? "speaker.wave.2.fill" : (activation.isListening ? "mic.fill" : "mic.slash")) {
      ActivationMenu(activation: activation, voice: voice, glow: glow)
    }
  }
}

/// App-scoped events remain connected when the last window closes.
@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
  private var model: AppModel?
  private var observers: [NSObjectProtocol] = []
  private var wakeObserver: NSObjectProtocol?
  private var refreshTimer: Timer?
  private var voice: VoiceExperienceController?
  private var glow: ScreenEdgeGlowController?
  private var voiceLifecycle: VoiceLifecycleBridge?

  func connect(_ model: AppModel, voice: VoiceExperienceController, glow: ScreenEdgeGlowController) -> Bool {
    guard self.model == nil else { return false }
    self.model = model
    self.voice = voice
    self.glow = glow
    let center = NotificationCenter.default
    for name in [NSApplication.didBecomeActiveNotification,
      NSNotification.Name.NSSystemClockDidChange, NSNotification.Name.NSSystemTimeZoneDidChange] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in await self?.model?.refresh() }
      })
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in await self?.model?.refresh() }
      }
    voiceLifecycle = VoiceLifecycleBridge(onSuspend: { [weak self] reason in
      self?.voice?.suspend(reason: reason)
      self?.glow?.hide()
    }, onResume: { [weak self] reason in
      await self?.voice?.resume(reason: reason)
    })
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.model?.refresh()
      }
    }
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationWillTerminate(_ notification: Notification) { stopActivation() }

  private func stopActivation() {
    voiceLifecycle?.stop()
    voice?.suspend(reason: .sessionInactive)
    glow?.hide()
  }
}

@MainActor private final class VoiceFeedbackRelay {
  weak var voice: VoiceExperienceController?
}

private enum AppStartupError: Error { case bundledAppRequired }

private struct ActivationMenu: View {
  let activation: ActivationController
  let voice: VoiceExperienceController
  let glow: ScreenEdgeGlowController
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(voice.statusText)
    Button("Open ARGUS") {
      openWindow(id: "argus-main")
      NSApp.activate(ignoringOtherApps: true)
    }
    Divider()
    if activation.isEnabled || voice.alwaysListen || voice.isSpeaking {
      Button("Stop listening") { voice.stopListening(); glow.hide() }
    } else {
      Button("Enable listening…") {
        // Consent and mode selection stay in the visible app, not a background action.
        openWindow(id: "argus-main")
        NSApp.activate(ignoringOtherApps: true)
      }
    }
    Button("Preview edge glow") { activation.preview() }
    Divider()
    Button("Quit ARGUS") {
      voice.suspend(reason: .sessionInactive)
      glow.hide()
      NSApp.terminate(nil)
    }
  }
}
