import AppKit

/// App-scoped observation. Events are delivered synchronously on the main actor;
/// the consumer owns consent and decides whether a matching resume is allowed.
@MainActor public final class ActivationSuspensionMonitor {
  private let observations = SuspensionObservations()

  public convenience init(workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    lockCenter: NotificationCenter = DistributedNotificationCenter.default(),
    onSuspend: @escaping @MainActor @Sendable () -> Void) {
    self.init(workspaceCenter: workspaceCenter, lockCenter: lockCenter,
      onLifecycleChange: { _, suspended in if suspended { onSuspend() } })
  }

  public init(workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    lockCenter: NotificationCenter = DistributedNotificationCenter.default(),
    onLifecycleChange: @escaping @MainActor @Sendable (VoiceSuspensionReason, Bool) -> Void) {
    let workspaceEvents: [(Notification.Name, VoiceSuspensionReason, Bool)] = [
      (NSWorkspace.willSleepNotification, .systemSleep, true),
      (NSWorkspace.didWakeNotification, .systemSleep, false),
      (NSWorkspace.screensDidSleepNotification, .displaySleep, true),
      (NSWorkspace.screensDidWakeNotification, .displaySleep, false),
      (NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true),
      (NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false),
    ]
    let lockEvents: [(Notification.Name, VoiceSuspensionReason, Bool)] = [
      (Notification.Name("com.apple.screenIsLocked"), .screenLock, true),
      (Notification.Name("com.apple.screenIsUnlocked"), .screenLock, false),
    ]
    for (center, events) in [(workspaceCenter, workspaceEvents), (lockCenter, lockEvents)] {
      for (name, reason, suspended) in events {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in
          // Revoke before returning, not in a Task behind a ready permission result.
          MainActor.assumeIsolated { onLifecycleChange(reason, suspended) }
        }
        observations.values.append((center, observer))
      }
    }
  }

  public func stopObserving() { observations.removeAll() }

  deinit {
    let observations = observations
    Task { @MainActor in observations.removeAll() }
  }
}

@MainActor private final class SuspensionObservations {
  var values: [(NotificationCenter, NSObjectProtocol)] = []
  func removeAll() {
    for (center, observer) in values { center.removeObserver(observer) }
    values.removeAll()
  }
}
