import AppKit
import Testing
@testable import ArgusPresentation

@MainActor struct VoiceLifecycleBridgeTests {
  @Test func startupIsUnknownAndWakeDoesNotPretendUnlock() async {
    let workspace = NotificationCenter(), locks = NotificationCenter()
    var suspended: [VoiceSuspensionReason] = [], resumed: [VoiceSuspensionReason] = []
    let bridge = VoiceLifecycleBridge(workspaceCenter: workspace, lockCenter: locks,
      onSuspend: { suspended.append($0) }, onResume: { resumed.append($0) })
    defer { bridge.stop() }
    #expect(suspended == [.startupUnverified])
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    await drain()
    #expect(resumed.contains(.systemSleep))
    #expect(resumed.contains(.sessionInactive))
    #expect(!resumed.contains(.startupUnverified))
    locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    await drain()
    #expect(resumed.suffix(2) == [.screenLock, .startupUnverified])
  }

  @Test func queuedUnlockCannotUndoNewLock() async {
    let workspace = NotificationCenter(), locks = NotificationCenter()
    var suspended: [VoiceSuspensionReason] = [], resumed: [VoiceSuspensionReason] = []
    let bridge = VoiceLifecycleBridge(workspaceCenter: workspace, lockCenter: locks,
      onSuspend: { suspended.append($0) }, onResume: { resumed.append($0) })
    defer { bridge.stop() }
    locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    locks.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
    #expect(suspended.last == .screenLock)
    await drain()
    #expect(resumed.isEmpty)
  }

  @Test func independentWakeEventsSurviveAndStopInvalidatesQueuedWork() async {
    let workspace = NotificationCenter(), locks = NotificationCenter()
    var resumed: [VoiceSuspensionReason] = []
    let bridge = VoiceLifecycleBridge(workspaceCenter: workspace, lockCenter: locks,
      onSuspend: { _ in }, onResume: { resumed.append($0) })
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    await drain()
    #expect(Set(resumed) == [.systemSleep, .displaySleep])
    let previousCount = resumed.count
    locks.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    bridge.stop()
    await drain()
    #expect(resumed.count == previousCount)
  }

  private func drain() async { for _ in 0..<50 { await Task.yield() } }
}
