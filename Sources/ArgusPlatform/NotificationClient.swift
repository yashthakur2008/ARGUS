import ArgusCore

public enum NotificationAuthorization: String, Sendable, Equatable {
  case notDetermined, denied, authorized, provisional
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
