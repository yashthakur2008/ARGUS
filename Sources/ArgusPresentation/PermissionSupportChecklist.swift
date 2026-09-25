public struct PermissionSupportItem: Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let detail: String
  public let requestActionTitle: String?
  public let systemSettingsTitle: String?

  public init(id: String, title: String, detail: String, requestActionTitle: String?, systemSettingsTitle: String?) {
    self.id = id
    self.title = title
    self.detail = detail
    self.requestActionTitle = requestActionTitle
    self.systemSettingsTitle = systemSettingsTitle
  }
}

public enum PermissionSupportChecklist {
  public static let defaultItems: [PermissionSupportItem] = [
    PermissionSupportItem(id: "notifications", title: "Notifications",
      detail: "Needed to show reminder alerts. macOS may still suppress banners with Focus or notification settings.",
      requestActionTitle: "Request notification access", systemSettingsTitle: "Open Notification settings"),
    PermissionSupportItem(id: "microphone", title: "Microphone",
      detail: "Needed for clap detection and wake-name listening. ARGUS only listens after you turn listening on.",
      requestActionTitle: "Request microphone access", systemSettingsTitle: "Open Microphone settings"),
    PermissionSupportItem(id: "speech", title: "Speech Recognition",
      detail: "Needed only for wake-name detection. ARGUS requires on-device recognition and does not use hosted speech fallback.",
      requestActionTitle: "Request speech recognition", systemSettingsTitle: "Open Speech Recognition settings"),
    PermissionSupportItem(id: "accessibility", title: "Accessibility",
      detail: "macOS only lists ARGUS here after the app asks to be trusted. Use this if ARGUS is absent from Privacy & Security > Accessibility.",
      requestActionTitle: "Request Accessibility listing", systemSettingsTitle: "Open Accessibility settings"),
    PermissionSupportItem(id: "elevenlabs", title: "ElevenLabs spoken responses",
      detail: "Needed only for spoken responses. Save an API key and accept text-transmission consent before testing voice.",
      requestActionTitle: nil, systemSettingsTitle: nil),
    PermissionSupportItem(id: "launchAtLogin", title: "Launch at login",
      detail: "Optional. This starts ARGUS after login, but it does not grant microphone or speech permissions.",
      requestActionTitle: nil, systemSettingsTitle: nil)
  ]
}
