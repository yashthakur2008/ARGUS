import SwiftUI
import ArgusCore

struct ReminderEditor: View {
  var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State var draft: ReminderDraft
  var context: String? = nil
  @State private var validationError: String?
  @State private var isSaving = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(draft.original == nil ? "New reminder" : "Edit reminder").font(.title2.weight(.semibold))
      if let context { Text(context).font(.callout).foregroundStyle(.secondary) }
      Form {
        TextField("Title", text: $draft.title).accessibilityLabel("Reminder title")
        DatePicker("Date & time", selection: $draft.dueAt, displayedComponents: [.date, .hourAndMinute])
          .environment(\.timeZone, TimeZone(identifier: draft.timeZoneID) ?? .current)
        Picker("Time zone", selection: $draft.timeZoneID) {
          ForEach(Array(Set(TimeZone.knownTimeZoneIdentifiers + ["UTC", "GMT", draft.timeZoneID])).sorted(), id: \.self) {
            Text($0.replacingOccurrences(of: "_", with: " ")).tag($0)
          }
        }.accessibilityLabel("Reminder time zone")
        Text("Changing the time zone keeps the same instant. Adjust the date and time afterward to change the deadline.")
          .font(.caption).foregroundStyle(.secondary)
        Toggle("Repeat every weekday", isOn: $draft.weekdays)
        if draft.weekdays, let original = draft.original,
          original.dueAt == draft.dueAt, original.timeZoneID == draft.timeZoneID,
          case let .weekdays(hour, minute) = original.recurrence {
          Text("Existing weekday time: \(String(format: "%02d:%02d", hour, minute)). Changing the date/time or zone updates it. A DST gap may shift only the first deadline.")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          Text("Weekday reminders use the selected local time, Monday through Friday.")
            .font(.caption).foregroundStyle(.secondary)
        }
        TextField("Alert minutes before", text: $draft.alertMinutes)
          .accessibilityLabel("Alert offsets in minutes, comma separated")
        Text("Use 0 for at the deadline, or 0, 10, 30. Up to 8 alerts. Leave blank for no notifications.")
          .font(.caption).foregroundStyle(.secondary)
      }.formStyle(.grouped).disabled(isSaving)
      if let validationError { Text(validationError).foregroundStyle(.red).font(.callout) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isSaving)
        Spacer()
        Button("Save reminder") {
          guard !isSaving, !model.isWorking else { return }
          isSaving = true
          let submittedDraft = draft
          Task {
            let saved = await model.save(submittedDraft)
            isSaving = false
            if saved { dismiss() }
            else { validationError = model.message }
          }
        }.keyboardShortcut(.defaultAction).disabled(model.isWorking || isSaving)
      }
    }.padding(24).frame(width: 520).interactiveDismissDisabled(isSaving)
  }
}

struct SnoozeEditor: View {
  var model: AppModel
  let reminder: Reminder
  @State var until: Date
  @State private var validationError: String?
  @State private var isSubmitting = false
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Snooze reminder").font(.title2.weight(.semibold))
      Text(reminder.title)
      DatePicker("Remind me at", selection: $until, displayedComponents: [.date, .hourAndMinute])
        .environment(\.timeZone, TimeZone(identifier: reminder.timeZoneID) ?? .current)
        .disabled(isSubmitting)
      Text(reminder.timeZoneID).font(.caption).foregroundStyle(.secondary)
      Text("Your original deadline stays unchanged.").font(.caption).foregroundStyle(.secondary)
      if let validationError { Text(validationError).foregroundStyle(.red).font(.callout) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isSubmitting)
        Spacer()
        Button("Snooze") {
          guard !isSubmitting, !model.isWorking, until > model.referenceDate else { return }
          isSubmitting = true
          let submittedUntil = until
          Task {
            defer { isSubmitting = false }
            if await model.snooze(reminder, until: submittedUntil) { dismiss() }
            else { validationError = model.message ?? "Could not snooze. Please review the reminder and try again." }
          }
        }
          .keyboardShortcut(.defaultAction).disabled(until <= model.referenceDate || model.isWorking || isSubmitting)
      }
    }.padding(24).frame(width: 430).interactiveDismissDisabled(isSubmitting)
  }
}
