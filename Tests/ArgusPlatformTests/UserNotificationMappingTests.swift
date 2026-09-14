import Foundation
import UserNotifications
import Testing
import ArgusCore
@testable import ArgusPlatform

struct UserNotificationMappingTests {
  @Test func mapsPrivateContentUTCAndIdentity() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let item = NotificationIntent(id: "argus.reminder.fixture", reminderID: UUID(), title: "Private fixture", fireAt: now.addingTimeInterval(600), sourceRevision: 2)
    let request = try UserNotificationMapping.request(for: item, now: now)
    #expect(request.identifier == item.id)
    #expect(request.content.body == "A reminder needs your attention")
    #expect(!request.content.title.contains(item.title))
    #expect((request.trigger as? UNCalendarNotificationTrigger)?.dateComponents.timeZone == TimeZone(secondsFromGMT: 0))
    #expect(UserNotificationMapping.intent(from: request)?.reminderID == item.reminderID)
    #expect(UserNotificationMapping.intent(from: request)?.sourceRevision == 2)
    #expect(UserNotificationMapping.intent(from: request)?.fireAt == item.fireAt)
  }
}
extension UserNotificationMappingTests {
  @Test func rejectsUnownedOrPastRequests() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(throws: (any Error).self) {
      try UserNotificationMapping.request(for: NotificationIntent(id: "another.app", reminderID: UUID(), title: "x", fireAt: now.addingTimeInterval(60), sourceRevision: 1), now: now)
    }
    #expect(throws: (any Error).self) {
      try UserNotificationMapping.request(for: NotificationIntent(id: "argus.reminder.expired", reminderID: UUID(), title: "x", fireAt: now, sourceRevision: 1), now: now)
    }
  }
  @Test func rejectsMalformedPendingRecord() {
    let content = UNMutableNotificationContent()
    content.userInfo = ["reminderID": UUID().uuidString, "sourceRevision": "invalid"]
    let request = UNNotificationRequest(identifier: "argus.reminder.invalid", content: content, trigger: nil)
    #expect(UserNotificationMapping.intent(from: request) == nil)
  }
}
extension UserNotificationMappingTests {
  @Test func fractionalFutureRoundsTriggerUpAndPreservesIntent() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000.2)
    let intent = NotificationIntent(id: "argus.reminder.fractional", reminderID: UUID(), title: "Private fraction", fireAt: Date(timeIntervalSince1970: 1_800_000_000.8), sourceRevision: 9)
    let request = try UserNotificationMapping.request(for: intent, now: now)
    let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    #expect(calendar.date(from: trigger.dateComponents) == Date(timeIntervalSince1970: 1_800_000_001))
    #expect(UserNotificationMapping.intent(from: request) == intent)
  }
  @Test func roundingBeyondSupportedDateIsRejected() {
    let intent = NotificationIntent(id: "argus.reminder.limit", reminderID: UUID(), title: "Fixture", fireAt: Date(timeIntervalSince1970: 253_402_300_799.5), sourceRevision: 1)
    #expect(throws: (any Error).self) {
      try UserNotificationMapping.request(for: intent, now: Date(timeIntervalSince1970: 0))
    }
  }
}
extension UserNotificationMappingTests {
  @Test func foregroundPolicyPresentsOwnedValidRequestsWithoutFocusBypass() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let intent = NotificationIntent(id: "argus.reminder.foreground", reminderID: UUID(), title: "Fixture", fireAt: now.addingTimeInterval(60), sourceRevision: 1)
    let request = try UserNotificationMapping.request(for: intent, now: now)
    #expect(UserNotificationMapping.foregroundOptions(for: request) == [.banner, .sound])
    let foreign = UNNotificationRequest(identifier: "other.app", content: request.content, trigger: request.trigger)
    #expect(UserNotificationMapping.foregroundOptions(for: foreign).isEmpty)
  }
}
