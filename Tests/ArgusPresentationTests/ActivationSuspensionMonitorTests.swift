import AppKit
import Testing
@testable import ArgusPresentation

@MainActor struct ActivationSuspensionMonitorTests {
  @Test func suspensionRevokesConsentBeforeNotificationReturns() {
    let workspace = NotificationCenter()
    let locks = NotificationCenter()
    var stops = 0
    let monitor = ActivationSuspensionMonitor(workspaceCenter: workspace, lockCenter: locks) {
      stops += 1
    }
    defer { monitor.stopObserving() }
    for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
      NSWorkspace.sessionDidResignActiveNotification] {
      let before = stops
      workspace.post(name: name, object: nil)
      #expect(stops == before + 1)
    }
    let beforeLock = stops
    locks.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
    #expect(stops == beforeLock + 1)
  }

  @Test func stoppedMonitorDoesNotReceiveFurtherEvents() {
    let workspace = NotificationCenter()
    let locks = NotificationCenter()
    var stops = 0
    let monitor = ActivationSuspensionMonitor(workspaceCenter: workspace, lockCenter: locks) {
      stops += 1
    }
    monitor.stopObserving()
    monitor.stopObserving()
    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    locks.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
    #expect(stops == 0)
  }
}
