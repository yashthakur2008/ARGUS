import SwiftUI
import AppKit
import ArgusPlatform
import ArgusStore

public struct SettingsView: View {
  var model: AppModel
  var activation: ActivationController?
  var appearance: AppearanceSettings?
  var voice: VoiceExperienceController?
  var login: LoginItemController?
  var elevenLabs: ElevenLabsSettingsModel?
  var permissionRequester: (any SystemPermissionRequesting)?
  var updateModel: GitHubUpdateModel?
  @State private var policyEditor: PolicyEditorSession?
  @State private var presentedIssue: SettingsIssue?
  public init(model: AppModel, activation: ActivationController? = nil, appearance: AppearanceSettings? = nil,
    voice: VoiceExperienceController? = nil, login: LoginItemController? = nil,
    elevenLabs: ElevenLabsSettingsModel? = nil, permissionRequester: (any SystemPermissionRequesting)? = nil,
    updateModel: GitHubUpdateModel? = nil) {
    self.model = model
    self.activation = activation
    self.appearance = appearance
    self.voice = voice
    self.login = login
    self.elevenLabs = elevenLabs
    self.permissionRequester = permissionRequester
    self.updateModel = updateModel
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
      AppUpdateSection(info: AppUpdateInfo(), updateModel: updateModel)
      PermissionSupportSection(model: model, requester: permissionRequester)
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

private struct AppUpdateSection: View {
  let info: AppUpdateInfo
  let updateModel: GitHubUpdateModel?

  var body: some View {
    Section("What's new") {
      VStack(alignment: .leading, spacing: 8) {
        Text(info.versionLine).font(.headline)
        Text(info.commitLine).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        Text(info.recoveryLine).font(.caption).foregroundStyle(.secondary)
        if info.latestEntry == nil {
          Label(info.freshnessLine, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange)
        } else {
          Label(info.freshnessLine, systemImage: "checkmark.seal")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if let entry = info.latestEntry {
        DisclosureGroup(entry.title) {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(entry.items, id: \.self) { item in
              Text("• \(item)").frame(maxWidth: .infinity, alignment: .leading)
            }
          }.font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
      } else {
        Text("Build ARGUS again with scripts/build-dev-app.sh to bundle CHANGELOG.md and the current Git commit.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Button("Copy version info") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info.copyText, forType: .string)
      }
      .accessibilityHint("Copies the app version, build, Git commit, and bundled changelog summary")
      if let updateModel {
        GitHubUpdateStatusView(model: updateModel)
      }
    }
    .task { await updateModel?.check() }
  }
}

private struct GitHubUpdateStatusView: View {
  let model: GitHubUpdateModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.isChecking {
        Label("Checking GitHub for updates…", systemImage: "arrow.triangle.2.circlepath")
          .font(.callout).foregroundStyle(.secondary)
      }
      if let status = model.status {
        Label(status.title, systemImage: status.showsUpdatePrompt ? "sparkles" : "checkmark.seal")
          .font(.headline).foregroundStyle(status.showsUpdatePrompt ? .orange : .secondary)
        Text(status.message).font(.callout).foregroundStyle(.secondary)
        if let current = status.currentCommit, let latest = status.latestCommit {
          Text("Current: \(current) · GitHub: \(latest)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        } else if let latest = status.latestCommit {
          Text("GitHub: \(latest)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        HStack {
          if let url = status.latestCommitURL {
            Button("View latest commit") { NSWorkspace.shared.open(url) }
          }
          Button("View PR") { NSWorkspace.shared.open(GitHubUpdateChecker.pullRequestURL) }
          Button("Copy rebuild command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(status.copyCommand, forType: .string)
          }
        }
      }
      if let error = model.errorMessage {
        Text(error).font(.caption).foregroundStyle(.orange)
      }
      Button("Check GitHub for updates") { Task { await model.check() } }
        .disabled(model.isChecking)
    }.padding(.vertical, 4)
  }
}

private struct PermissionSupportSection: View {
  let model: AppModel
  let requester: (any SystemPermissionRequesting)?

  var body: some View {
    Section("Permissions") {
      Text("If ARGUS is missing from a macOS Privacy & Security list, use the request button first, then open the matching System Settings pane.")
        .font(.callout).foregroundStyle(.secondary)
      ForEach(PermissionSupportChecklist.defaultItems) { item in
        VStack(alignment: .leading, spacing: 6) {
          Text(item.title).font(.headline)
          Text(item.detail).font(.caption).foregroundStyle(.secondary)
          HStack {
            if let action = item.requestActionTitle {
              Button(action) { request(item.id) }
                .disabled(requester == nil && item.id != "notifications")
            }
            if let systemSettingsTitle = item.systemSettingsTitle {
              Button(systemSettingsTitle) { openSettings(item.id) }
            }
          }
        }.padding(.vertical, 4)
      }
    }
  }

  private func request(_ id: String) {
    switch id {
    case "notifications": Task { await model.enableNotifications() }
    case "microphone": Task { _ = await requester?.requestMicrophone() }
    case "speech": Task { _ = await requester?.requestSpeechRecognition() }
    case "accessibility": _ = requester?.requestAccessibilityListing()
    default: break
    }
  }

  private func openSettings(_ id: String) {
    let url: String = switch id {
    case "notifications": "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    case "microphone": "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    case "speech": "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
    case "accessibility": "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    default: "x-apple.systempreferences:com.apple.preference.security"
    }
    if let url = URL(string: url) { NSWorkspace.shared.open(url) }
  }
}
