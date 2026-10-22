import ArgusCore

public enum StoreError: Error, Equatable, Sendable {
  case sqlite(code: Int32, message: String)
  case conflict
  case corruption(String)
  case unsupportedSchema(Int64)
  case noticeNotFound(String)
  case noticeDismissed(String)
  case noticeNoLongerApplicable(String)
  case invalidSnooze
  case activeSnoozeConflict
  case revisionOverflow
}

extension StoreError: UserFacingFailure {
  public var userFacingReason: String {
    switch self {
    case .sqlite:
      "ARGUS could not reach its local database. Reopen the app, and check that its data directory is accessible."
    case .conflict:
      "That reminder changed somewhere else. Reload it and try again."
    case .corruption:
      "ARGUS found damaged local data and stopped rather than using it. Existing reminders were not replaced."
    case .unsupportedSchema:
      "This data was written by a different version of ARGUS. Update to the matching build before using it."
    case .noticeNotFound:
      "That notice is no longer available."
    case .noticeDismissed:
      "That notice was already dismissed."
    case .noticeNoLongerApplicable:
      "That notice no longer matches the current reminder."
    case .invalidSnooze:
      "That snooze time is not valid. Snoozing moves the alert without changing the deadline."
    case .activeSnoozeConflict:
      "That reminder is already snoozed. Review the active snooze first."
    case .revisionOverflow:
      "That reminder has been edited too many times to track further. Recreate it."
    }
  }
}
