import SwiftUI

@MainActor public struct ElevenLabsSettingsView: View {
  private let model: ElevenLabsSettingsModel
  @State private var apiKeyInput = ""
  @State private var confirmRemoval = false

  public init(model: ElevenLabsSettingsModel) { self.model = model }

  public var body: some View {
    Section("ElevenLabs voice") {
      LabeledContent("Voice ID", value: model.voiceID)
        .textSelection(.enabled)
      Text("This is the only spoken-response voice. There is no system-voice fallback.")
        .font(.caption).foregroundStyle(.secondary)
      Text(model.statusText).font(.caption)
      if let error = model.errorMessage {
        Text(error).font(.caption).foregroundStyle(.red)
      }
      SecureField("ElevenLabs API key", text: $apiKeyInput)
        .textContentType(.password)
        .autocorrectionDisabled()
        .accessibilityIdentifier("elevenlabs-api-key")
      HStack {
        Button("Save to Keychain") {
          defer { apiKeyInput = "" }
          model.save(apiKeyInput)
        }
        .disabled(apiKeyInput.isEmpty)
        Button("Check Keychain") { model.refresh() }
        Button("Remove saved key", role: .destructive) { confirmRemoval = true }
      }
      Toggle("Allow spoken-response text to be sent to ElevenLabs", isOn: Binding(
        get: { model.transmissionConsent }, set: { model.setTransmissionConsent($0) }))
      Text("When enabled, generated spoken-response text is sent to ElevenLabs with your API key. Provider usage may incur charges. Saving a key does not test it or send text.")
        .font(.caption).foregroundStyle(.secondary)
      Text("Development storage: macOS login Keychain, trusted to this application. This is not signed broker isolation. Rebuilds may lose access. Prompt encryption and signed-worker isolation are not enabled by this adapter.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .confirmationDialog("Remove the saved ElevenLabs API key?", isPresented: $confirmRemoval) {
      Button("Remove key", role: .destructive) { apiKeyInput = ""; model.remove() }
      Button("Cancel", role: .cancel) {}
    }
    .onDisappear { apiKeyInput = "" }
  }
}
