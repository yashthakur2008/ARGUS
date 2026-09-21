import SwiftUI
import ArgusPlatform
import ArgusStore

public struct SettingsView: View {
  var model: AppModel
  var activation: ActivationController?
  var appearance: AppearanceSettings?
  var voice: VoiceExperienceController?
  var login: LoginItemController?
  var elevenLabs: ElevenLabsSettingsModel?
  @State private var policyEditor: PolicyEditorSession?
  @State private var presentedIssue: SettingsIssue?
  public init(model: AppModel, activation: ActivationController? = nil, appearance: AppearanceSettings? = nil,
    voice: VoiceExperienceController? = nil, login: LoginItemController? = nil,
    elevenLabs: ElevenLabsSettingsModel? = nil) {
    self.model = model
    self.activation = activation
    self.appearance = appearance
    self.voice = voice
    self.login = login
    self.elevenLabs = elevenLabs
  }
  public var body: some View {
    Form {
      if let issue = primaryIssue {
        Section {
          SettingsIssueBanner(issue: issue) { presentedIssue = issue }
        }
      }
      if let voice, let login { VoiceSettingsView(voice: voice, login: login) }
      if let elevenLabs { ElevenLabsSettingsView(model: elevenLabs) }
      ActivationSettingsView(activation: activation, appearance: appearance, voice: voice)
      Section("Notifications") {
        Text(model.status)
        Text("Scheduled means macOS has a pending request, not that a banner was shown or seen. Focus, system settings, sleep and quitting ARGUS can affect timely reminders.")
          .font(.callout).foregroundStyle(.secondary)
        if model.result?.authorization == .notDetermined || model.result == nil {
          Button("Enable notifications") { Task { await model.enableNotifications() } }
            .disabled(model.isWorking).accessibilityHint("Requests native macOS notification permission")
        } else if model.result?.authorization == .denied {
          Text("Permission is denied. You can change ARGUS notification permission in System Settings, then refresh here.")
        }
        if let error = model.result?.error {
          DisclosureGroup("Scheduling details") {
            Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
          }
        }
        Button("Refresh notification status") { Task { await model.refresh() } }
        Text("Notification previews use generic text. Reminder content stays in local storage and notification metadata.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Quiet hours") {
        if let policy = model.recovery.policy {
          if let quiet = policy.quietHours {
            Text("\(String(format: "%02d:%02d", quiet.startHour, quiet.startMinute)) to \(String(format: "%02d:%02d", quiet.endHour, quiet.endMinute)) · \(quiet.timeZoneID)")
          } else { Text("No quiet-hours deferral") }
          if policy.bypassQuietHours { Text("ARGUS quiet-hours bypass is enabled").foregroundStyle(.orange) }
          Button("Edit quiet hours…") {
            policyEditor = PolicyEditorSession(draft: NotificationPolicyDraft(policy: policy, timeZone: .current))
          }.disabled(model.isWorking)
        } else { Text("Refresh to load local notification settings.").foregroundStyle(.secondary) }
        Text("This local policy never bypasses macOS Focus or notification permission.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("This development slice") {
        Text("Reminders are stored locally using SQLite. The database is not encrypted by ARGUS.")
        Text("Closing the window leaves ARGUS running. Quit stops new scheduling. Already pending macOS notifications may still appear.")
        Text("The schedule is checked at launch, after changes, on wake and periodically while the app is running. No login item or background helper is installed.")
        Text("Notices record due scheduled times, not OS delivery. Recurring recovery scans seven elapsed days. History is retained until the source reminder is deleted.")
          .foregroundStyle(.secondary)
      }
    }.formStyle(.grouped).padding(16).frame(minWidth: 500, minHeight: 400)
      .tint(appearance?.color ?? Color(red: 101 / 255, green: 200 / 255, blue: 145 / 255))
      .sheet(item: $policyEditor) { session in QuietHoursEditor(model: model, draft: session.draft) }
      .alert(item: $presentedIssue) { issue in
        Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK")))
      }
  }

  private var primaryIssue: SettingsIssue? {
    voice?.settingsIssue ?? elevenLabs?.setupIssue ?? notificationIssue
  }

  private var notificationIssue: SettingsIssue? {
    guard model.result?.authorization == .denied else { return nil }
    return SettingsIssue(id: "notification-denied", title: "Notifications need permission",
      message: "ARGUS can save reminders locally, but macOS notification permission is denied. Allow notifications in System Settings, then refresh notification status.",
      primaryAction: "Review notifications")
  }
}

private struct PolicyEditorSession: Identifiable { let id = UUID(); let draft: NotificationPolicyDraft }
