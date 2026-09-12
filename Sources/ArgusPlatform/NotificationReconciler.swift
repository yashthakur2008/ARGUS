import Foundation
import ArgusCore
import ArgusStore

/// Reconciles durable desired state with the OS boundary. A successful result means
/// pending requests matched at the observed generation, never that an alert delivered.
public actor NotificationReconciler {
  private let store: ReminderStore
  private let client: any NotificationClient
  private var running = false
  private var dirty = false
  private var latestWindow: (now: Date, horizon: Date)?
  private var waiters: [CheckedContinuation<ReconciliationResult, Never>] = []

  public init(store: ReminderStore, client: any NotificationClient) {
    self.store = store
    self.client = client
  }

  /// Concurrent calls join a single flight and request a rerun using the latest window.
  /// A continuously changing source is bounded to 16 passes and reported as pending.
  public func reconcile(now: Date, horizon: Date) async -> ReconciliationResult {
    latestWindow = (now, horizon)
    dirty = true
    if running {
      return await withCheckedContinuation { waiters.append($0) }
    }
    running = true
    var result = ReconciliationResult(scheduledCount: 0, authorization: .notDetermined,
      generation: -1, isPending: true, error: "Reconciliation has not completed")
    for _ in 0..<16 {
      dirty = false
      let window = latestWindow ?? (now, horizon)
      let pass = await reconcilePass(now: window.now, horizon: window.horizon)
      result = pass.result
      if !pass.stale && !dirty { break }
      result = ReconciliationResult(scheduledCount: 0, authorization: result.authorization,
        generation: result.generation, isPending: true, error: "Desired state or authorization changed during reconciliation; retry required")
    }
    running = false
    let joined = waiters
    waiters.removeAll()
    for waiter in joined { waiter.resume(returning: result) }
    return result
  }

  private func reconcilePass(now: Date, horizon: Date) async -> (result: ReconciliationResult, stale: Bool) {
    var generation: Int64 = -1
    var authorization = NotificationAuthorization.notDetermined
    func outcome(_ error: String?, count: Int = 0, stale: Bool = false) -> (ReconciliationResult, Bool) {
      (ReconciliationResult(scheduledCount: count, authorization: authorization,
        generation: generation, isPending: error != nil || stale, error: error), stale)
    }
    do {
      generation = try store.generation()
      let desired = try store.desiredNotifications(now: now, horizon: horizon)
      guard try store.generation() == generation else { return outcome(nil, stale: true) }
      authorization = await client.authorizationStatus()
      guard try store.generation() == generation else { return outcome(nil, stale: true) }
      let pending = try await client.pending().filter { $0.id.hasPrefix(NotificationIntent.identifierPrefix) }
      guard try await isCurrent(generation: generation, authorization: authorization) else { return outcome(nil, stale: true) }
      let allowed = authorization == .authorized || authorization == .provisional
      if !allowed {
        await client.remove(ids: pending.map(\.id))
        guard try await isCurrent(generation: generation, authorization: authorization) else { return outcome(nil, stale: true) }
        return outcome("Notification authorization is \(authorization.rawValue)")
      }
      let desiredIDs = Set(desired.map(\.id))
      let obsolete = pending.filter { !desiredIDs.contains($0.id) }.map(\.id)
      if !obsolete.isEmpty {
        await client.remove(ids: obsolete)
        guard try await isCurrent(generation: generation, authorization: authorization) else { return outcome(nil, stale: true) }
      }
      for intent in desired where !pending.contains(intent) {
        try await client.add(intent)
        guard try await isCurrent(generation: generation, authorization: authorization) else { return outcome(nil, stale: true) }
      }
      // Verify, rather than treating adapter acceptance as evidence of OS state.
      let verified = try await client.pending().filter { $0.id.hasPrefix(NotificationIntent.identifierPrefix) }
      guard try await isCurrent(generation: generation, authorization: authorization) else { return outcome(nil, stale: true) }
      guard verified.count == desired.count,
        verified.sorted(by: { $0.id < $1.id }) == desired.sorted(by: { $0.id < $1.id }) else {
        return outcome("Pending notifications do not match desired state")
      }
      return outcome(nil, count: desired.count)
    } catch {
      return outcome(String(describing: error))
    }
  }

  private func isCurrent(generation: Int64, authorization: NotificationAuthorization) async throws -> Bool {
    let currentAuthorization = await client.authorizationStatus()
    let currentGeneration = try store.generation()
    return currentAuthorization == authorization && currentGeneration == generation
  }
}
