import Foundation
import ArgusCore

public struct ReminderDraft {
  public var original: Reminder?
  public var title: String
  public var dueAt: Date
  public var timeZoneID: String
  public var weekdays: Bool
  public var alertMinutes: String

  public init(original: Reminder? = nil, now: Date, timeZone: TimeZone) {
    self.original = original
    title = original?.title ?? ""
    dueAt = original?.dueAt ?? now.addingTimeInterval(3600)
    timeZoneID = original?.timeZoneID ?? timeZone.identifier
    weekdays = original?.recurrence != nil
    alertMinutes = (original?.alertOffsets ?? [0]).map { String($0 / 60) }.joined(separator: ", ")
  }

  private func keepsSnooze(_ recurrence: RecurrenceRule?) -> Bool {
    original?.dueAt == dueAt && original?.recurrence == recurrence && original?.timeZoneID == timeZoneID
  }

  public func reminder(now: Date) throws -> Reminder {
    guard let zone = TimeZone(identifier: timeZoneID) else { throw CoreError.invalidTimeZone(timeZoneID) }
    let offsets: [TimeInterval]
    if alertMinutes.trimmingCharacters(in: .whitespaces).isEmpty { offsets = [] }
    else {
      offsets = try alertMinutes.split(separator: ",", omittingEmptySubsequences: false).map {
        guard let value = Double($0.trimmingCharacters(in: .whitespaces)), value.isFinite, value >= 0 else {
          throw PresentationError.invalidAlertMinutes
        }
        return value * 60
      }
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let recurrence: RecurrenceRule? = weekdays
      ? .weekdays(hour: calendar.component(.hour, from: dueAt), minute: calendar.component(.minute, from: dueAt)) : nil
    return try Reminder(id: original?.id ?? UUID(), title: title, dueAt: dueAt,
      timeZoneID: timeZoneID, createdAt: original?.createdAt ?? now, updatedAt: now,
      revision: original?.revision ?? 1, alertOffsets: offsets, recurrence: recurrence,
      snoozedUntil: keepsSnooze(recurrence) ? original?.snoozedUntil : nil,
      snoozedOccurrenceAt: keepsSnooze(recurrence) ? original?.snoozedOccurrenceAt : nil,
      isCompleted: original?.isCompleted ?? false)
  }
}
