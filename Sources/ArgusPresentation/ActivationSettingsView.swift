import SwiftUI
import ArgusCore
import ArgusPlatform

/// Settings sections for a shared, explicitly enabled activation session and local accent.
public struct ActivationSettingsView: View {
  var activation: ActivationController?
  var appearance: AppearanceSettings?
  var voice: VoiceExperienceController?
  @State private var hexDraft = ""
  @State private var invalidHex = false

  public init(activation: ActivationController? = nil, appearance: AppearanceSettings? = nil,
    voice: VoiceExperienceController? = nil) {
    self.activation = activation
    self.appearance = appearance
    self.voice = voice
  }

  public var body: some View {
    Group {
      if let activation {
        Section("Local activation") {
          Label(activation.statusText, systemImage: activation.isListening ? "mic.fill" : "mic.slash")
            .accessibilityIdentifier("activation.status")
          Picker("Listen for", selection: Binding(get: { activation.mode }, set: { mode in
            if let voice { Task { await voice.setMode(mode) } } else { activation.mode = mode }
          })) {
            ForEach(ActivationMode.allCases, id: \.self) { mode in
              Text(mode.displayName).tag(mode)
            }
          }.disabled(activation.isEnabled)
          HStack {
            if let voice, voice.alwaysListen && !activation.isEnabled && !voice.isSpeaking {
              Button("Start listening") { voice.requestEnableOnce() }
                .disabled(!activation.canEnable)
                .accessibilityIdentifier("activation.resumeExplicitly")
            }
            if activation.isEnabled || voice?.alwaysListen == true || voice?.isSpeaking == true {
              Button("Stop listening", role: .destructive) {
                if let voice { voice.stopListening() } else { activation.stop() }
              }
                .accessibilityIdentifier("activation.stop")
            } else {
              Button("Start listening") {
                if let voice { voice.requestEnableOnce() }
                else { Task { await activation.enable() } }
              }
                .disabled(!activation.canEnable)
                .accessibilityHint("Requests microphone access. Name recognition also requires speech permission.")
                .accessibilityIdentifier("activation.enable")
            }
            Button("Preview glow") { activation.preview() }
              .accessibilityHint("Shows the edge color without using the microphone")
              .accessibilityIdentifier("activation.preview")
          }
          if !activation.isEnabled && !activation.canEnable {
            Text("Microphone off. Finish or dismiss the pending macOS permission prompt before enabling again.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if case .unavailable = activation.status, activation.mode != .clap {
            Button("Choose clap-only instead") {
              if let voice { Task { await voice.setMode(.clap) } } else { activation.mode = .clap }
            }
            Text(voice?.alwaysListen == true
              ? "Always listen is on. Choosing clap-only can resume listening if microphone permission is already allowed."
              : "This changes the selection only. Press Start listening when you are ready.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Text("Listening requires your opt-in. Microphone access is needed for claps. Saying ‘Argus’ also needs speech permission and supported on-device recognition. If it is unavailable, you can choose clap-only. ARGUS never switches modes silently or uses server recognition.")
            .font(.callout).foregroundStyle(.secondary)
          Text("Name activation currently uses US English on-device speech resources.")
            .font(.caption).foregroundStyle(.secondary)
          DisclosureGroup("Privacy and background listening") {
            VStack(alignment: .leading, spacing: 8) {
              Text("Audio is processed on this Mac. No audio files or transcripts are saved or sent. Activation shows a brief glow and can speak a fixed response when Spoken responses is enabled. It does not execute commands or change reminders.")
              Text("Sharp sounds can be mistaken for claps. Use Stop listening to mute immediately.")
              Text("Closing a window leaves listening active while ARGUS runs. Sleep and lock pause listening. Always listen can resume after unlock, but Stop listening disables it. A cold launch waits for an unlock signal or Start listening. Launch at login is a separate opt-in. Quit stops all audio.")
            }.font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      if let appearance {
        Section("Appearance") {
          HStack(spacing: 12) {
            Circle().fill(appearance.color).frame(width: 22, height: 22)
              .accessibilityLabel("Current accent \(appearance.hexString)")
            Text("A little green, a little watchful").font(.callout)
          }
          HStack {
            TextField("Hex RGB", text: $hexDraft).textFieldStyle(.roundedBorder)
              .frame(maxWidth: 170).onSubmit { applyHex(appearance) }
              .accessibilityIdentifier("appearance.hex")
            Button("Apply color") { applyHex(appearance) }
              .accessibilityIdentifier("appearance.apply")
          }
          if invalidHex {
            Text("Use six hexadecimal digits, such as #65C891. Your previous color is unchanged.")
              .font(.caption).foregroundStyle(.red)
          }
          HStack {
            preset("Argus green", hex: AppearanceSettings.presetGreen, appearance: appearance)
            preset("Forest", hex: "#38A878", appearance: appearance)
            preset("Lavender", hex: "#AD9CE3", appearance: appearance)
          }
          Toggle("Reduce motion", isOn: Binding(get: { appearance.reduceMotion },
            set: { appearance.setReduceMotion($0) }))
            .accessibilityIdentifier("appearance.reduceMotion")
          Text("System Reduce Motion is always respected. This override also disables the brief glow pulse and orb transitions.")
            .font(.caption).foregroundStyle(.secondary)
          Text("The accent and screen-edge glow color are saved only on this Mac. Preview never turns on listening.")
            .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { hexDraft = appearance.hexString }
        .onChange(of: appearance.hexString) { _, value in hexDraft = value; invalidHex = false }
      }
    }
  }

  private func applyHex(_ appearance: AppearanceSettings) {
    invalidHex = !appearance.setHex(hexDraft)
    if !invalidHex { hexDraft = appearance.hexString }
  }

  private func preset(_ title: String, hex: String, appearance: AppearanceSettings) -> some View {
    Button(title) {
      appearance.setHex(hex)
      hexDraft = appearance.hexString
      invalidHex = false
    }.buttonStyle(.bordered)
  }
}
