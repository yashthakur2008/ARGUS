import Foundation
import Testing
import ArgusCore
import ArgusStore
@testable import ArgusPresentation

struct NotificationPolicyDraftTests {
  @Test func preservesExplicitZoneBypassAndRevision() throws {
    let quiet = try QuietHours(startHour: 23, startMinute: 15, endHour: 7, endMinute: 30, timeZoneID: "Asia/Kolkata")
    let original = try NotificationPolicy(quietHours: quiet, bypassQuietHours: true, revision: 4)
    let draft = NotificationPolicyDraft(policy: original, timeZone: .current)
    #expect(try draft.policy() == original)
  }
  @Test func rejectsInvalidWallTimeAndDisablesQuietHoursExplicitly() throws {
    var draft = NotificationPolicyDraft(policy: try NotificationPolicy(), timeZone: .current)
    draft.enabled = true; draft.startHour = 25
    #expect(throws: (any Error).self) { try draft.policy() }
    draft.enabled = false
    #expect(try draft.policy().quietHours == nil)
  }
}
