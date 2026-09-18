import AppKit

/// App-scoped observation only. Never resumes listening or requests permission.
@MainActor public final class ActivationSuspensionMonitor {
  private let observations = SuspensionObservations()

  public init(workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    lockCenter: NotificationCenter = DistributedNotificationCenter.default(),
    onSuspend: @escaping @MainActor @Sendable () -> Void) {
    let workspaceNames = [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
      NSWorkspace.sessionDidResignActiveNotification]
    let registrations = workspaceNames.map { (workspaceCenter, $0) }
      + [(lockCenter, NSNotification.Name("com.apple.screenIsLocked"))]
    for (center, name) in registrations {
      let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in
        // The observer explicitly delivers on OperationQueue.main. Revoke consent
        // before returning, rather than enqueueing behind a ready permission result.
        MainActor.assumeIsolated { onSuspend() }
      }
      observations.values.append((center, observer))
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
