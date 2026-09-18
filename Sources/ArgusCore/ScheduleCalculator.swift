import Foundation

public enum ScheduleCalculator {
  /// Plans strictly after now, up to and including horizon. Quiet hours never alter dueAt.
  /// A snooze replaces its persisted occurrence, never changing the source deadline.
  /// bypassQuietHours is explicit app policy, never a request to bypass OS Focus.
  public static func notifications(
    for reminder: Reminder, now: Date, horizon: Date,
    quietHours: QuietHours? = nil, bypassQuietHours: Bool = false
  ) throws -> [NotificationIntent] {
    try plannedNotifications(
      for: reminder, now: now, horizon: horizon,
      quietHours: quietHours, bypassQuietHours: bypassQuietHours
    ).map(\.intent)
  }

  /// Same delivery plan, retaining sorted unique original occurrences after coalescing.
  /// includingStart enables historical [now, horizon] capture without an invalid predecessor date.
  public static func plannedNotifications(
    for reminder: Reminder, now: Date, horizon: Date,
    quietHours: QuietHours? = nil, bypassQuietHours: Bool = false, includingStart: Bool = false
  ) throws -> [PlannedNotification] {
    try reminder.validate()
    try validateDate(now)
    try validateDate(horizon)
    guard horizon >= now else { throw CoreError.invalidHorizon }
    guard !reminder.isCompleted, includingStart || horizon > now else { return [] }
    let zone = try validatedZone(reminder.timeZoneID)
    var occurrencesByFireDate: [Date: Set<Date>] = [:]

    func include(_ candidate: Date, occurrence: Date) throws {
      try validateDate(candidate)
      guard candidate <= horizon else { return }
      let fireAt =
        bypassQuietHours ? candidate : quietHours?.nextAllowedDate(for: candidate) ?? candidate
      try validateDate(fireAt)
      guard includingStart ? fireAt >= now : fireAt > now, fireAt <= horizon else { return }
      occurrencesByFireDate[fireAt, default: []].insert(occurrence)
      guard occurrencesByFireDate.count <= 64 else { throw CoreError.notificationLimitExceeded }
    }

    if let snooze = reminder.snoozedUntil {
      try include(snooze, occurrence: reminder.snoozedOccurrenceAt ?? reminder.dueAt)
    }
    // Legacy records without a target retain their original anchor semantics, never infer
    // an identity from updatedAt (which can change on rename) or the moving planning clock.
    let snoozedOccurrence =
      reminder.snoozedUntil == nil ? nil : reminder.snoozedOccurrenceAt ?? reminder.dueAt
    let offsets = try normalizedOffsets(reminder.alertOffsets)
    let searchStart = bypassQuietHours ? now : quietHours?.candidateSearchStart(for: now) ?? now
    for offset in offsets {
      if snoozedOccurrence != reminder.dueAt {
        try include(reminder.dueAt.addingTimeInterval(-offset), occurrence: reminder.dueAt)
      }
      guard let rule = reminder.recurrence else { continue }
      // Search each offset separately, avoiding iteration across years of past occurrences.
      var after = max(reminder.dueAt, searchStart.addingTimeInterval(offset))
      let lastDue = horizon.addingTimeInterval(offset)
      try validateDate(after)
      try validateDate(lastDue)
      if includingStart {
        // Include an exact recurring boundary without searching before the valid anchor.
        after = after.addingTimeInterval(-min(1, after.timeIntervalSince(reminder.dueAt)))
      }
      var occurrence = try rule.nextOccurrence(after: after, timeZone: zone)
      while occurrence <= lastDue {
        if occurrence != snoozedOccurrence {
          try include(occurrence.addingTimeInterval(-offset), occurrence: occurrence)
        }
        let next = try rule.nextOccurrence(after: occurrence, timeZone: zone)
        guard next > occurrence else { throw CoreError.invalidRecurrence }
        occurrence = next
      }
    }
    return occurrencesByFireDate.keys.sorted().map { fireAt in
      // Exact IEEE bits avoid locale formatting and randomized hashing in persisted IDs.
      let key = String(fireAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
      let intent = NotificationIntent(
        id: NotificationIntent.identifierPrefix + reminder.id.uuidString.lowercased() + "." + key,
        reminderID: reminder.id, title: reminder.title, fireAt: fireAt,
        sourceRevision: reminder.revision)
      return PlannedNotification(
        intent: intent, occurrenceDates: Array(occurrencesByFireDate[fireAt, default: []]))
    }
  }
}
