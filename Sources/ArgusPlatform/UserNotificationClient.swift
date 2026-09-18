import Foundation
import UserNotifications
import ArgusCore

/// Construct only at the native app composition root, never in CLI tests.
public actor UserNotificationClient: NotificationClient {
  private let presentationDelegate = UserNotificationPresentationDelegate()
  private let center: UNUserNotificationCenter
  private let clock: @Sendable () -> Date

  public init(center: UNUserNotificationCenter, clock: @escaping @Sendable () -> Date) {
    self.center = center
    self.clock = clock
    center.delegate = presentationDelegate
  }

  public func authorizationStatus() async -> NotificationAuthorization {
    let status = await withCheckedContinuation { continuation in
      center.getNotificationSettings { continuation.resume(returning: $0.authorizationStatus) }
    }
    switch status {
    case .authorized: return .authorized
    case .provisional, .ephemeral: return .provisional
    case .denied: return .denied
    case .notDetermined: return .notDetermined
    @unknown default: return .denied
    }
  }

  /// Only the explicit Enable notifications control may invoke this method.
  public func requestAuthorization() async throws {
    let _: Bool = try await withCheckedThrowingContinuation { continuation in
      center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: granted) }
      }
    }
  }

  public func pending() async throws -> [NotificationIntent] {
    try await withCheckedThrowingContinuation { continuation in
      center.getPendingNotificationRequests { requests in
        do {
          let intents = try UserNotificationMapping.pendingIntents(from: requests)
          continuation.resume(returning: intents)
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  public func add(_ intent: NotificationIntent) async throws {
    let request = try UserNotificationMapping.request(for: intent, now: clock())
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      center.add(request) { error in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
      }
    }
  }

  public func remove(ids: [String]) async {
    center.removePendingNotificationRequests(withIdentifiers: ids.filter { $0.hasPrefix(NotificationIntent.identifierPrefix) })
  }
}

/// Foreground presentation asks for ordinary banners/sound only. macOS permission,
/// Focus and notification settings remain authoritative. No critical alert bypass.
private final class UserNotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler(UserNotificationMapping.foregroundOptions(for: notification.request))
  }
}
