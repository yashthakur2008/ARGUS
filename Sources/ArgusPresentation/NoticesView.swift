import SwiftUI
import ArgusCore
import ArgusStore

struct NoticesView: View {
  var model: AppModel
  @State private var showHistory = false
  @State private var editor: NoticeEditorSession?
  @State private var snooze: NoticeSnoozeSession?

  private var shownNotices: [ReminderNotice] {
    showHistory ? model.recovery.notices : model.recovery.activeNotices
  }

  var noticeIssue: String? { model.noticesUnavailableMessage ?? model.recovery.issue }
  var emptyTitle: String { model.noticesUnavailableMessage == nil ? "No notices here" : "Notices unavailable" }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Notices").font(.system(size: 32, weight: .semibold, design: .rounded))
      Text("Due reminders, not delivery receipts. Recurring catch-up covers the last seven days. One-time overdue alerts remain available.")
        .font(.callout).foregroundStyle(.secondary)
      Picker("Notice filter", selection: $showHistory) {
        Text("Needs attention").tag(false)
        Text("History · all notices").tag(true)
      }.pickerStyle(.segmented)
      if let issue = noticeIssue {
        Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
      }
      if model.noticesUnavailableMessage != nil {
        Button("Retry loading notices") { Task { await model.refresh() } }
          .disabled(model.isWorking || model.isReconciling)
      }
      if shownNotices.isEmpty {
        ContentUnavailableView(emptyTitle, systemImage: "bell", description: Text("Notices are saved when a scheduled reminder time becomes due."))
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(shownNotices) { notice in row(notice) }
          }
        }
      }
      Text("Dismiss affects only a notice. Rescheduling retains the old notice until separately dismissed. Deleting a source removes its related history.")
        .font(.caption).foregroundStyle(.secondary)
    }.padding(30)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .sheet(item: $editor) { session in
        ReminderEditor(model: model, draft: session.draft,
          context: "This notice remains in history and needs separate dismissal, even if you reschedule its source.")
      }
      .sheet(item: $snooze) { session in
        NoticeSnoozeEditor(model: model, notice: session.notice, source: session.source,
          until: model.referenceDate.addingTimeInterval(600),
          occurrence: session.notice.occurrenceDates.count == 1 ? session.notice.occurrenceDates.first : nil)
      }
  }

  private func row(_ notice: ReminderNotice) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(notice.titleSnapshot).font(.body.weight(.medium))
        Spacer()
        if notice.dismissedAt != nil { Label("Dismissed", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary) }
      }
      Text("Scheduled \(notice.scheduledAt.formatted(date: .abbreviated, time: .shortened)) · \(TimeZone.current.identifier)")
        .font(.caption).foregroundStyle(.secondary)
      if notice.occurrenceDates.count > 1 {
        Text("\(notice.occurrenceDates.count) source occurrences share this alert. Choose one explicitly when snoozing.")
          .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Button("Open") { editSource(notice) }
        Button("Reschedule…") { editSource(notice) }
        if notice.dismissedAt == nil {
          Button("Snooze…") {
            if let source = model.recovery.open(notice) {
              snooze = NoticeSnoozeSession(notice: notice, source: source)
            }
          }
          Spacer()
          Button("Dismiss") { Task { await model.dismissNotice(notice) } }
        }
      }.disabled(model.isWorking)
    }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
  }

  private func editSource(_ notice: ReminderNotice) {
    if let source = model.recovery.open(notice) {
      editor = NoticeEditorSession(draft: ReminderDraft(original: source, now: model.referenceDate, timeZone: .current))
    }
  }
}

private struct NoticeEditorSession: Identifiable { let id = UUID(); let draft: ReminderDraft }
private struct NoticeSnoozeSession: Identifiable { let id = UUID(); let notice: ReminderNotice; let source: Reminder }

private struct NoticeSnoozeEditor: View {
  var model: AppModel
  let notice: ReminderNotice
  let source: Reminder
  @State var until: Date
  @State var occurrence: Date?
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Snooze this notice").font(.title2.weight(.semibold))
      Text(source.title)
      Picker("Source occurrence", selection: $occurrence) {
        Text("Choose an occurrence").tag(nil as Date?)
        ForEach(notice.occurrenceDates, id: \.self) { date in
          Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
            timeZone: TimeZone(identifier: source.timeZoneID) ?? .current))).tag(Optional(date))
        }
      }.accessibilityLabel("Exact source occurrence to snooze")
      DatePicker("Remind me at", selection: $until, displayedComponents: [.date, .hourAndMinute])
        .environment(\.timeZone, TimeZone(identifier: source.timeZoneID) ?? .current)
      Text(source.timeZoneID).font(.caption).foregroundStyle(.secondary)
      Text("The source deadline stays unchanged. Only this notice is dismissed. Other notices remain independently dismissible.")
        .font(.callout).foregroundStyle(.secondary)
      if let error { Text(error).font(.callout).foregroundStyle(.red) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Snooze selected occurrence") {
          Task {
            if await model.snoozeNotice(notice, occurrenceAt: occurrence, until: until, expectedRevision: source.revision) { dismiss() }
            else { error = model.recovery.issue }
          }
        }.keyboardShortcut(.defaultAction).disabled(occurrence == nil || model.isWorking)
      }
    }.padding(24).frame(width: 520)
  }
}
