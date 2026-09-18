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
  private var latestWindow: (now: Date, horizon: Date?)?
  private var highestRequestSequence: Int?
  private var lastCompletion: ReconciliationResult?
  private var waiters: [CheckedContinuation<ReconciliationResult, Never>] = []

  public init(store: ReminderStore, client: any NotificationClient) {
    self.store = store
    self.client = client
  }

  public func reconcileSystemNotifications(now: Date) async -> ReconciliationResult {
    await run(now: now, horizon: nil)
  }

  /// One logical owner supplies increasing tokens; an equal token is the same
  /// request. AppModel owns a private instance and uses only this entrypoint.
  /// Obsolete calls join active work or reuse its completion without new I/O.
  /// Mixing public unsequenced calls preserves their arrival-based overrides,
  /// but forfeits ordered-window provenance. The sequence watermark never resets.
  package func reconcileSystemNotifications(now: Date, requestSequence: Int) async -> ReconciliationResult {
    await run(now: now, horizon: nil, requestSequence: requestSequence)
  }

  /// Concurrent calls join a single flight and request a rerun using the latest window.
  /// A continuously changing source is bounded to 16 passes and reported as pending.
  public func reconcile(now: Date, horizon: Date) async -> ReconciliationResult {
    await run(now: now, horizon: horizon)
  }

  /// Admission and logical window selection are one synchronous actor operation.
  /// Internal visibility permits deterministic reordered-admission tests while
  /// the actual reconciliation pass is gated at the fake notification boundary.
  func admitWindow(now: Date, horizon: Date?, requestSequence: Int?) -> Bool {
    if let requestSequence {
      if let highestRequestSequence, requestSequence <= highestRequestSequence { return false }
      highestRequestSequence = requestSequence
    }
    latestWindow = (now, horizon)
    dirty = true
    return true
  }

  private func run(now: Date, horizon: Date?, requestSequence: Int? = nil) async -> ReconciliationResult {
    let admitted = admitWindow(now: now, horizon: horizon, requestSequence: requestSequence)
    if running {
      return await withCheckedContinuation { waiters.append($0) }
    }
    if !admitted, let lastCompletion { return lastCompletion }
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
    lastCompletion = result
    let joined = waiters
    waiters.removeAll()
    for waiter in joined { waiter.resume(returning: result) }
    return result
  }

  private func reconcilePass(now: Date, horizon: Date?) async -> (result: ReconciliationResult, stale: Bool) {
    var generation: Int64 = -1
    var authorization = NotificationAuthorization.notDetermined
    func outcome(_ error: String?, count: Int = 0, stale: Bool = false) -> (ReconciliationResult, Bool) {
      (ReconciliationResult(scheduledCount: count, authorization: authorization,
        generation: generation, isPending: error != nil || stale, error: error), stale)
    }
    do {
      generation = try store.generation()
      let desired: [NotificationIntent]
      if let horizon { desired = try store.desiredNotifications(now: now, horizon: horizon) }
      else { desired = try store.desiredSystemNotifications(now: now) }
      guard try store.generation() == generation else { return outcome(nil, stale: true) }
      authorization = await client.authorizationStatus()
      guard try store.generation() == generation else { return outcome(nil, stale: true) }
      let pending: [NotificationIntent]
      do {
        pending = try await client.pending().filter { $0.id.hasPrefix(NotificationIntent.identifierPrefix) }
      } catch PendingNotificationError.malformedOwnedRequests(let ids) {
        // Enumeration stays read-only. Only this fenced path may recover known
        // current/legacy corruption. Never turn arbitrary adapter errors into deletes.
        guard !ids.isEmpty, ids.allSatisfy({ $0.hasPrefix(NotificationIntent.identifierPrefix) }) else {
          return outcome("Invalid malformed-notification recovery IDs; no requests removed")
        }
        guard try await isCurrent(generation: generation, authorization: authorization) else { return outcome(nil, stale: true) }
        await client.remove(ids: ids)
        guard try await isCurrent(generation: generation, authorization: authorization) else { return outcome(nil, stale: true) }
        // One cleanup attempt per pass. A failed read, surviving corruption or
        // unsupported version fails closed, rather than repeatedly deleting IDs.
        let verified = try await client.pending()
        guard try await isCurrent(generation: generation, authorization: authorization) else { return outcome(nil, stale: true) }
        let removedIDs = Set(ids)
        guard !verified.contains(where: { removedIDs.contains($0.id) }) else {
          return outcome("Malformed pending notification removal could not be verified; retry required")
        }
        pending = verified.filter { $0.id.hasPrefix(NotificationIntent.identifierPrefix) }
        // OS removal is by ID, not compare-and-delete. These generation fences
        // cannot protect a same-ID replacement made by an independent writer.
      }
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
        do {
          guard try await isCurrent(generation: generation, authorization: authorization) else {
            // This completed side effect is already known to be stale. Do not depend
            // on another pending read or planning pass to clean up its owned ID.
            await removeKnownAddedIntent(intent)
            return outcome(nil, stale: true)
          }
        } catch {
          // If freshness cannot be established, leave no unverified completed add.
          await removeKnownAddedIntent(intent)
          throw error
        }
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

  private func removeKnownAddedIntent(_ intent: NotificationIntent) async {
    guard intent.id.hasPrefix(NotificationIntent.identifierPrefix) else { return }
    await client.remove(ids: [intent.id])
  }

  private func isCurrent(generation: Int64, authorization: NotificationAuthorization) async throws -> Bool {
    let currentAuthorization = await client.authorizationStatus()
    let currentGeneration = try store.generation()
    return currentAuthorization == authorization && currentGeneration == generation
  }
}
