import SwiftUI
import AppKit

/// Independent preferences backed by shared coordinators, not duplicate view-local state.
public struct VoiceSettingsView: View {
  private let voice: VoiceExperienceController
  private let login: LoginItemController
  @Environment(\.scenePhase) private var scenePhase

  public init(voice: VoiceExperienceController, login: LoginItemController) {
    self.voice = voice
    self.login = login
  }

  public var body: some View {
    Group {
      Section("Voice experience") {
        if let issue = voice.settingsIssue {
          SettingsIssueBanner(issue: issue) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
          }
        }
        Toggle("Always listen", isOn: Binding(
          get: { voice.alwaysListen },
          set: { voice.requestAlwaysListen($0) }
        ))
        .accessibilityIdentifier("voice.alwaysListen")
        .accessibilityHint("Remembers your choice while ARGUS runs. Turning off stops listening and speech.")
        Toggle("Spoken responses", isOn: Binding(
          get: { voice.spokenResponses }, set: { voice.setSpokenResponses($0) }
        ))
        .accessibilityIdentifier("voice.spokenResponses")
        Label(voice.statusText, systemImage: voice.isSpeaking ? "speaker.wave.2.fill" : "mic")
          .accessibilityIdentifier("voice.status")
        Text("Mode and live state: \(voice.statusText). If claps or ‘Argus’ are not detected, confirm the selected activation mode below, macOS Microphone permission, and Speech Recognition permission for name activation.")
          .font(.caption).foregroundStyle(.secondary)
        HStack {
          Button("Test voice") { voice.previewSpeech() }
            .disabled(!voice.spokenResponses)
            .accessibilityIdentifier("voice.preview")
            .accessibilityHint("Sends a fixed sample to ElevenLabs only with text-transmission consent and a saved API key.")
          Button("Stop listening", role: .destructive) { voice.stopListening() }
            .accessibilityIdentifier("voice.stop")
            .accessibilityHint("Stops listening and speech, and turns off Always listen.")
        }
        Text("Always listen remembers your opt-in. Sleep and locking pause listening. It resumes only when your Mac is available and microphone and speech permissions are already allowed. After a cold launch, ARGUS waits for an observed unlock or an explicit Start listening action. It does not infer the initial lock state. Stop listening turns off the remembered opt-in.")
          .font(.caption).foregroundStyle(.secondary)
        Text("Spoken responses use only your selected ElevenLabs voice. With separate text-transmission consent, fixed response text is sent to ElevenLabs. Microphone audio, transcripts and reminders are not sent by this voice adapter. No system voice is used if ElevenLabs is unavailable. You can keep listening on with spoken responses off.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Launch at login") {
        Toggle("Launch at login", isOn: Binding(
          get: { login.isEnabled }, set: { login.setEnabled($0) }
        ))
        .disabled(login.isWorking || login.status == .unavailable || login.status == .requiresApproval)
        .accessibilityIdentifier("login.enabled")
        Text(login.statusText)
          .font(.callout).foregroundStyle(.secondary)
          .accessibilityIdentifier("login.status")
        if login.status == .requiresApproval {
          Button("Cancel pending login registration", role: .destructive) { login.setEnabled(false) }
            .disabled(login.isWorking)
            .accessibilityIdentifier("login.cancelApproval")
        }
        if let error = login.errorMessage {
          Text(error).font(.callout).foregroundStyle(.red)
            .accessibilityIdentifier("login.error")
        }
        Button("Refresh login status") { login.refresh() }
          .disabled(login.isWorking)
          .accessibilityIdentifier("login.refresh")
        Text("Login registration and microphone permission are separate. Launch at login does not enable listening. Quit stops ARGUS completely. No helper keeps listening after Quit.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .onAppear { login.refresh() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { login.refresh() }
    }
  }
}
