import AppKit

/// Bridges native events to the voice policy without allowing a queued old unlock
/// to undo a newer lock. Independent reasons retain independent event generations.
@MainActor public final class VoiceLifecycleBridge {
  private var monitor: ActivationSuspensionMonitor?
  private var generations: [VoiceSuspensionReason: UInt64] = [:]
  private var tasks: [VoiceSuspensionReason: Task<Void, Never>] = [:]
  private var stopped = false
  private let onSuspend: @MainActor @Sendable (VoiceSuspensionReason) -> Void
  private let onResume: @MainActor @Sendable (VoiceSuspensionReason) async -> Void

  public init(workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    lockCenter: NotificationCenter = DistributedNotificationCenter.default(),
    onSuspend: @escaping @MainActor @Sendable (VoiceSuspensionReason) -> Void,
    onResume: @escaping @MainActor @Sendable (VoiceSuspensionReason) async -> Void) {
    self.onSuspend = onSuspend
    self.onResume = onResume
    // Public session APIs do not establish initial screen-lock state. A cold launch
    // waits for an observed unlock or an explicit user listening action.
    onSuspend(.startupUnverified)
    monitor = ActivationSuspensionMonitor(workspaceCenter: workspaceCenter, lockCenter: lockCenter,
      onLifecycleChange: { [weak self] reason, suspended in
        self?.receive(reason: reason, suspended: suspended)
      })
  }

  private func receive(reason: VoiceSuspensionReason, suspended: Bool) {
    guard !stopped else { return }
    let generation = (generations[reason] ?? 0) &+ 1
    generations[reason] = generation
    tasks[reason]?.cancel()
    tasks[reason] = nil
    if suspended {
      onSuspend(reason)
      return
    }
    tasks[reason] = Task { @MainActor [weak self] in
      guard let self, self.isCurrent(reason, generation) else { return }
      await self.onResume(reason)
      guard self.isCurrent(reason, generation) else { return }
      if reason == .screenLock { await self.onResume(.startupUnverified) }
      guard self.isCurrent(reason, generation) else { return }
      self.tasks[reason] = nil
    }
  }

  private func isCurrent(_ reason: VoiceSuspensionReason, _ generation: UInt64) -> Bool {
    !stopped && !Task.isCancelled && generations[reason] == generation
  }

  public func stop() {
    stopped = true
    monitor?.stopObserving()
    monitor = nil
    for task in tasks.values { task.cancel() }
    tasks.removeAll()
  }
}
