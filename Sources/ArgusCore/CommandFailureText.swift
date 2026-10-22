import Foundation

/// A failure that already knows how to describe itself to a user.
///
/// Error types live in different layers, so each one supplies its own wording
/// instead of a single switch that lower layers cannot see.
public protocol UserFacingFailure {
  var userFacingReason: String { get }
}

/// Explains a failure in the user's terms.
///
/// Interpolating the raw error put Swift enum syntax such as
/// `unsupportedCommand` or `sqlite(code: 11, ...)` in front of users, which
/// names an internal case rather than the thing they did or how to fix it.
public enum CommandFailureText {
  public static func message(for error: Error, examples: String) -> String {
    "\(reason(for: error)) \(examples)"
  }

  public static func reason(for error: Error) -> String {
    guard let failure = error as? UserFacingFailure else {
      return "Something went wrong and the action was not applied."
    }
    return failure.userFacingReason
  }
}

extension CoreError: UserFacingFailure {
  public var userFacingReason: String {
    switch self {
    case .unsupportedCommand:
      "ARGUS did not recognize that command. It understands a small fixed set of phrases, and the wording must match closely."
    case .invalidTitle:
      "That reminder needs a title of 1 to 200 characters."
    case .invalidDuration:
      "That amount of time is not usable. Use a whole number of minutes, hours, or days, such as 20 minutes."
    case .invalidDate:
      "That date or time is not valid."
    case .invalidTimeZone:
      "That time zone is not recognized."
    case .invalidOffsets:
      "Those alert offsets are not usable. Give up to eight values such as 10m, 1h, or 2d, separated by commas."
    case .invalidRecurrence:
      "That repeat rule is not valid. Use a 24-hour time such as every weekday at 09:00."
    case .invalidSnooze:
      "That snooze time is not valid. Snoozing moves the alert without changing the deadline."
    case .invalidRevision:
      "That reminder changed somewhere else. Reload and try again."
    case .invalidQuietHours:
      "Those quiet hours are not valid."
    case .invalidHorizon:
      "That scheduling window is not valid."
    case .notificationLimitExceeded:
      "That would exceed the notification limit macOS allows. Remove some alerts or reminders first."
    }
  }
}
