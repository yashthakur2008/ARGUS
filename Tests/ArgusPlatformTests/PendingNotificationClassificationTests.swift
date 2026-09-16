import Foundation
import UserNotifications
import Testing
import ArgusCore
@testable import ArgusPlatform

struct PendingNotificationClassificationTests {
  @Test func foreignMetadataNeverBlocksOwnedSnapshot() throws {
    let requests = ["other.app", "argus.reminder", "other.argus.reminder.fixture"].map {
      request(id: $0, version: "999")
    }
    #expect(try UserNotificationMapping.pendingIntents(from: requests).isEmpty)
  }

  @Test func preservesValidCurrentAndLegacyIntents() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let intent = NotificationIntent(id: "argus.reminder.fixture", reminderID: UUID(),
      title: "Fixture", fireAt: now.addingTimeInterval(60), sourceRevision: 1)
    let current = try UserNotificationMapping.request(for: intent, now: now)
    #expect(try UserNotificationMapping.pendingIntents(from: [current]) == [intent])
    let content = UNMutableNotificationContent()
    content.userInfo = ["reminderID": intent.reminderID.uuidString, "sourceRevision": "1",
      "sourceTitle": intent.title, "fireAt": intent.fireAt.timeIntervalSince1970]
    let legacy = UNNotificationRequest(identifier: intent.id, content: content, trigger: current.trigger)
    #expect(try UserNotificationMapping.pendingIntents(from: [legacy]) == [intent])
  }

  @Test func malformedSupportedOwnedIDsAreExplicit() {
    let ids = ["argus.reminder.broken", "argus.reminder."]
    for version: String? in [nil, "2"] {
      #expect(throws: PendingNotificationError.malformedOwnedRequests(ids: ids.sorted())) {
        try UserNotificationMapping.pendingIntents(from: ids.map { request(id: $0, version: version) })
      }
    }
  }

  @Test func unknownAndAmbiguousVersionsTakePrecedenceOverMalformedRecords() {
    for version: Any in ["999", "3", "1", "", "02", 2, 999, NSNull()] {
      let id = "argus.reminder.future"
      let content = UNMutableNotificationContent()
      content.userInfo = ["mappingVersion": version]
      let future = UNNotificationRequest(identifier: id, content: content, trigger: nil)
      let malformed = request(id: "argus.reminder.broken", version: "2")
      for requests in [[malformed, future], [future, malformed]] {
        #expect(throws: PendingNotificationError.unsupportedMappingVersions(ids: [id])) {
          try UserNotificationMapping.pendingIntents(from: requests)
        }
      }
    }
  }

  private func request(id: String, version: String?) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    if let version { content.userInfo = ["mappingVersion": version] }
    return UNNotificationRequest(identifier: id, content: content, trigger: nil)
  }
}
