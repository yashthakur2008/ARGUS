import ArgusCore

public enum NotificationAuthorization: String, Sendable, Equatable {
  case notDetermined, denied, authorized, provisional
}

/// A read-only pending snapshot may expose malformed IDs without inventing intents.
/// Unsupported versions take precedence over recoverable malformed requests.
public enum PendingNotificationError: Error, Sendable, Equatable, CustomStringConvertible {
  case malformedOwnedRequests(ids: [String])
  case unsupportedMappingVersions(ids: [String])

  public var description: String {
    switch self {
    case .malformedOwnedRequests(let ids):
      return "Malformed owned pending notifications: \(ids.joined(separator: ", ")). Retry reconciliation to remove and rebuild supported requests."
    case .unsupportedMappingVersions(let ids):
      return "Unsupported pending notification mapping version: \(ids.joined(separator: ", ")). Update ARGUS before retrying. Automatic recovery is disabled for this snapshot."
    }
  }
}

extension PendingNotificationError: UserFacingFailure {
  /// These descriptions are already written for users and name the recovery
  /// action, so they are reused rather than replaced by generic wording.
  public var userFacingReason: String { description }
}

public protocol NotificationClient: Sendable {
  func authorizationStatus() async -> NotificationAuthorization
  func pending() async throws -> [NotificationIntent]
  func add(_ intent: NotificationIntent) async throws
  func remove(ids: [String]) async
}

public struct ReconciliationResult: Sendable, Equatable {
  public let scheduledCount: Int
  public let authorization: NotificationAuthorization
  public let generation: Int64
  public let isPending: Bool
  public let error: String?
}
