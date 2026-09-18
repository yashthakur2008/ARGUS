import Foundation

public enum ReminderCommand: Codable, Equatable, Sendable {
  case create(title: String, dueAt: Date, timeZoneID: String, recurrence: RecurrenceRule?)
  case list
  case delete(id: UUID)
  case snooze(id: UUID, until: Date)
  case edit(id: UUID, title: String?, dueAt: Date?)
  case setAlerts(id: UUID, offsets: [TimeInterval])
  case help
}
