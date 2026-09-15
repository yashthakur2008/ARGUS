import SwiftUI
import ArgusStore

struct QuietHoursEditor: View {
  var model: AppModel
  @State var draft: NotificationPolicyDraft
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Quiet hours").font(.title2.weight(.semibold))
      Form {
        Toggle("Defer alerts during quiet hours", isOn: $draft.enabled)
        clockFields("Start", hour: $draft.startHour, minute: $draft.startMinute).disabled(!draft.enabled)
        clockFields("End", hour: $draft.endHour, minute: $draft.endMinute).disabled(!draft.enabled)
        Picker("Time zone", selection: $draft.timeZoneID) {
          ForEach(Array(Set(TimeZone.knownTimeZoneIdentifiers + ["UTC", "GMT", draft.timeZoneID])).sorted(), id: \.self) {
            Text($0.replacingOccurrences(of: "_", with: " ")).tag($0)
          }
        }.disabled(!draft.enabled)
        Text("Equal start and end times disable deferral. Quiet hours change alert times, never source deadlines.")
          .font(.caption).foregroundStyle(.secondary)
        Toggle("Bypass ARGUS quiet hours", isOn: $draft.bypass)
        Text("This explicit override affects ARGUS only. It does not bypass macOS Focus, permission denial or system notification settings.")
          .font(.caption).foregroundStyle(.secondary)
      }.formStyle(.grouped)
      if let error { Text(error).font(.callout).foregroundStyle(.red) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Reload current settings") {
          Task {
            await model.refresh()
            if let policy = model.recovery.policy {
              draft = NotificationPolicyDraft(policy: policy, timeZone: .current)
              error = nil
            }
          }
        }.disabled(model.isWorking)
        Spacer()
        Button("Save") {
          Task {
            do {
              if await model.saveNotificationPolicy(try draft.policy(), expectedRevision: draft.revision) { dismiss() }
              else { error = model.recovery.issue }
            } catch { self.error = "Check the quiet-hours values: \(error)" }
          }
        }.keyboardShortcut(.defaultAction).disabled(model.isWorking)
      }
    }.padding(24).frame(width: 560)
  }

  private func clockFields(_ title: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
    HStack {
      Text(title)
      Spacer()
      Picker("\(title) hour", selection: hour) {
        ForEach(0..<24) { Text(String(format: "%02d", $0)).tag($0) }
      }.frame(width: 120)
      Picker("\(title) minute", selection: minute) {
        ForEach(0..<60) { Text(String(format: "%02d", $0)).tag($0) }
      }.frame(width: 120)
    }
  }
}
