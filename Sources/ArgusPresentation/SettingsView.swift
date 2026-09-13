import SwiftUI
import ArgusPlatform

public struct SettingsView: View {
  var model: AppModel
  public init(model: AppModel) { self.model = model }
  public var body: some View {
    Form {
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
        Button("Refresh notification status") { Task { await model.refresh() } }
        Text("Notification previews use generic text. Reminder content stays in local storage and notification metadata.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("This development slice") {
        Text("Reminders are stored locally using SQLite. The database is not encrypted by ARGUS.")
        Text("Closing the window leaves ARGUS running. Quit stops new scheduling. Already pending macOS notifications may still appear.")
        Text("The schedule is checked at launch, after changes, on wake and periodically while the app is running. No login item or background helper is installed.")
        Text("Quiet-hours preferences and durable missed-alert history are not available in this slice.")
          .foregroundStyle(.secondary)
      }
    }.formStyle(.grouped).padding(16).frame(minWidth: 500, minHeight: 400)
  }
}
