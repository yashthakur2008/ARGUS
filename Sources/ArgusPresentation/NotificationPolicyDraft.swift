import Foundation
import ArgusCore
import ArgusStore

public struct NotificationPolicyDraft {
  public let revision: Int64
  public var enabled: Bool
  public var startHour: Int
  public var startMinute: Int
  public var endHour: Int
  public var endMinute: Int
  public var timeZoneID: String
  public var bypass: Bool
  public init(policy: NotificationPolicy, timeZone: TimeZone) {
    revision = policy.revision
    enabled = policy.quietHours != nil
    startHour = policy.quietHours?.startHour ?? 22
    startMinute = policy.quietHours?.startMinute ?? 0
    endHour = policy.quietHours?.endHour ?? 8
    endMinute = policy.quietHours?.endMinute ?? 0
    timeZoneID = policy.quietHours?.timeZoneID ?? timeZone.identifier
    bypass = policy.bypassQuietHours
  }
  public func policy() throws -> NotificationPolicy {
    let quiet = enabled ? try QuietHours(startHour: startHour, startMinute: startMinute,
      endHour: endHour, endMinute: endMinute, timeZoneID: timeZoneID) : nil
    return try NotificationPolicy(quietHours: quiet, bypassQuietHours: bypass, revision: revision)
  }
}
