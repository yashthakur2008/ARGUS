import Foundation
import UserNotifications
import ArgusCore

public enum NotificationMappingError: Error { case invalidIntent, malformedPendingRequest }

/// Calendar triggers have second precision and round up, never before the requested instant.
/// Exact source timestamps stay in metadata for reconciliation.
/// Pure conversion only. This type never obtains the system notification center.
public enum UserNotificationMapping {
  public static func foregroundOptions(for request: UNNotificationRequest) -> UNNotificationPresentationOptions {
    intent(from: request) == nil ? [] : [.banner, .sound]
  }

  public static func request(for intent: NotificationIntent, now: Date) throws -> UNNotificationRequest {
    guard valid(intent), intent.fireAt > now else { throw NotificationMappingError.invalidIntent }
    let content = UNMutableNotificationContent()
    content.title = "ARGUS"
    content.body = "A reminder needs your attention"
    content.sound = .default
    content.userInfo = ["reminderID": intent.reminderID.uuidString,
      "sourceRevision": String(intent.sourceRevision), "sourceTitle": intent.title,
      "mappingVersion": "2",
      "fireAtReferenceBits": String(intent.fireAt.timeIntervalSinceReferenceDate.bitPattern)]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSinceReferenceDate: ceil(intent.fireAt.timeIntervalSinceReferenceDate)))
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    return UNNotificationRequest(identifier: intent.id, content: content, trigger: trigger)
  }

  public static func intent(from request: UNNotificationRequest) -> NotificationIntent? {
    let info = request.content.userInfo
    guard let rawID = info["reminderID"] as? String, let id = UUID(uuidString: rawID),
      let rawRevision = info["sourceRevision"] as? String, let revision = Int64(rawRevision),
      let title = info["sourceTitle"] as? String,
      let trigger = request.trigger as? UNCalendarNotificationTrigger, !trigger.repeats,
      trigger.dateComponents.timeZone == TimeZone(secondsFromGMT: 0)
    else { return nil }
    let fireAt: Date
    if let version = info["mappingVersion"] as? String {
      guard version == "2", let raw = info["fireAtReferenceBits"] as? String,
        let bits = UInt64(raw) else { return nil }
      fireAt = Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
    } else {
      // Legacy Unix metadata remains readable. If epoch conversion lost a bit,
      // exact reconciler equality replaces it with the versioned request.
      guard info["mappingVersion"] == nil, let timestamp = info["fireAt"] as? Double else { return nil }
      fireAt = Date(timeIntervalSince1970: timestamp)
    }
    let result = NotificationIntent(id: request.identifier, reminderID: id, title: title,
      fireAt: fireAt, sourceRevision: revision)
    guard valid(result) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let triggerDate = calendar.date(from: trigger.dateComponents),
      triggerDate.timeIntervalSinceReferenceDate == ceil(result.fireAt.timeIntervalSinceReferenceDate) else { return nil }
    return result
  }

  private static func valid(_ intent: NotificationIntent) -> Bool {
    let timestamp = intent.fireAt.timeIntervalSinceReferenceDate
    return intent.id.hasPrefix(NotificationIntent.identifierPrefix)
      && intent.id.count > NotificationIntent.identifierPrefix.count
      && intent.sourceRevision > 0 && !intent.title.isEmpty && intent.title.count <= 512
      && timestamp.isFinite && timestamp >= -63_113_904_000 && ceil(timestamp) < 252_423_993_600
  }
}
