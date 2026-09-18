import Foundation
import Observation
import ArgusCore
import ArgusStore
import ArgusPlatform

@MainActor @Observable
public final class AppModel {
  public var commandText = ""
  public private(set) var reminders: [Reminder] = []
  public private(set) var pendingDeletion: Reminder?
  public private(set) var message: String?
  public private(set) var result: ReconciliationResult?
  public private(set) var referenceDate: Date
  public private(set) var isWorking = false
  public private(set) var isReconciling = false
  public let recovery: ReminderRecoveryModel
  public let store: ReminderStore
  private let clock: @Sendable () -> Date
  private let reconciler: NotificationReconciler
  private let refreshLoader: any ReminderRefreshLoading
  private let draftWriter: any ReminderDraftWriting
  private var draftWriteInFlight = false
  private let requestPermission: (@Sendable () async throws -> Void)?
  private var readFailed = false
  private var refreshSequence = 0
  private var deletionRequestedAt: Date?
  public static let examples = "Try “remind me to Stretch in 20 minutes” or “every weekday at 09:00, Plan the day”."

  public convenience init(store: ReminderStore, client: any NotificationClient,
    clock: @escaping @Sendable () -> Date,
    requestPermission: (@Sendable () async throws -> Void)? = nil) {
    self.init(store: store, client: client, clock: clock, requestPermission: requestPermission,
      refreshLoader: ReminderRefreshLoader(store: store))
  }

  init(store: ReminderStore, client: any NotificationClient,
    clock: @escaping @Sendable () -> Date,
    requestPermission: (@Sendable () async throws -> Void)? = nil,
    refreshLoader: any ReminderRefreshLoading,
    draftWriter: (any ReminderDraftWriting)? = nil,
    reconciler: NotificationReconciler? = nil) {
    self.store = store
    self.recovery = ReminderRecoveryModel(store: store)
    self.clock = clock
    self.referenceDate = clock()
    self.reconciler = reconciler ?? NotificationReconciler(store: store, client: client)
    self.requestPermission = requestPermission
    self.refreshLoader = refreshLoader
    self.draftWriter = draftWriter ?? ReminderDraftWriter(store: store)
    recovery.onExplicitChange = { [weak self] in self?.invalidateRefresh() }
  }

  public var status: String {
    if readFailed { return "Local storage unavailable · schedule not verified" }
    if isReconciling { return "Saved locally · checking notification schedule" }
    guard let result else { return "Saved locally · schedule not checked" }
    if result.authorization == .denied { return "Saved locally · notification permission denied" }
    if result.authorization == .notDetermined { return "Saved locally · notifications not enabled" }
    if result.isPending || result.error != nil { return "Saved locally · scheduling pending" }
    return "Saved locally · \(result.scheduledCount) notifications scheduled with macOS"
  }

  public var noticesUnavailableMessage: String? {
    readFailed ? "Notices unavailable. Previously loaded history may be out of date. Retry loading notices to check current data." : nil
  }

  /// Reload consumers must distinguish retained cache from this request's accepted policy.
  func reloadNotificationPolicy() async -> RefreshPublicationOutcome {
    await refreshOutcome()
  }

  public func refresh() async {
    _ = await refreshOutcome()
  }

  /// The policy belongs to this accepted load, never a retained global cache.
  func refreshOutcome() async -> RefreshPublicationOutcome {
    guard !draftWriteInFlight else { return .superseded }
    refreshSequence += 1
    let sequence = refreshSequence
    let now = clock()
    referenceDate = now
    isReconciling = true
    let loaded = await refreshLoader.load(now: now, sequence: sequence)
    guard !draftWriteInFlight, sequence == refreshSequence else { return .superseded }
    let loadedPolicy: NotificationPolicy
    switch loaded {
    case .loaded(let loadedReminders, let notices, let policy):
      reminders = loadedReminders
      recovery.applyLoaded(notices: notices, policy: policy)
      loadedPolicy = policy
      if readFailed { message = nil }
      readFailed = false
    case .listFailure(let error):
      failRefresh(error)
      return .failed
    case .recoveryFailure(let loadedReminders, let error):
      reminders = loadedReminders
      failRefresh(error)
      return .failed
    }
    let checked = await reconciler.reconcileSystemNotifications(now: now, requestSequence: sequence)
    guard !draftWriteInFlight, sequence == refreshSequence else { return .superseded }
    result = checked
    isReconciling = false
    return .loaded(loadedPolicy)
  }

  private func failRefresh(_ error: String) {
    readFailed = true
    isReconciling = false
    result = nil
    message = "Could not read reminders: \(error)"
  }

  /// Successful local writes/publication invalidate pending loads, including direct
  /// recovery actions. External writes after a snapshot remain eventual until refresh.
  private func invalidateRefresh() {
    refreshSequence += 1
    result = nil
    isReconciling = false
  }

  public func submit(timeZone: TimeZone) async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    let input = commandText
    do {
      let now = clock()
      let command = try CommandParser.parse(input, now: now, timeZone: timeZone)
      message = nil
      switch command {
      case let .create(title, dueAt, zone, recurrence):
        let item = try Reminder(title: title, dueAt: dueAt, timeZoneID: zone,
          createdAt: now, updatedAt: now, recurrence: recurrence)
        try saveValidated(item, expectedRevision: nil, now: now)
      case .list: break
      case .help: message = Self.examples
      case let .delete(id): requestDeletion(try find(id))
      case let .snooze(id, until):
        try saveSnooze(try find(id), until: until, now: now)
      case let .edit(id, title, dueAt):
        try update(id, now: now) {
          if let title { $0.title = title }
          if let dueAt { $0.dueAt = dueAt; $0.snoozedUntil = nil; $0.snoozedOccurrenceAt = nil }
        }
      case let .setAlerts(id, offsets):
        try update(id, now: now) { $0.alertOffsets = offsets }
      }
      if commandText == input { commandText = "" }
      await refresh()
    } catch {
      message = "Could not apply command: \(error). \(Self.examples)"
    }
  }

  public func requestDeletion(_ reminder: Reminder) {
    pendingDeletion = reminder
    deletionRequestedAt = clock()
  }

  public func cancelDeletion() { pendingDeletion = nil; deletionRequestedAt = nil }

  public func confirmDeletion() async {
    guard !isWorking, let reviewed = pendingDeletion else { return }
    isWorking = true
    defer { isWorking = false }
    let requestedAt = deletionRequestedAt
    cancelDeletion()
    guard let requestedAt, clock().timeIntervalSince(requestedAt) >= 0,
      clock().timeIntervalSince(requestedAt) < 300 else {
      message = "Delete confirmation expired. Please review the reminder again."
      return
    }
    do {
      guard try find(reviewed.id) == reviewed else { throw StoreError.conflict }
      try store.delete(id: reviewed.id, expectedRevision: reviewed.revision)
      invalidateRefresh()
      message = nil
    } catch {
      message = "Reminder changed or could not be deleted. Please review it again. \(error)"
    }
    await refresh()
  }

  @discardableResult public func save(_ draft: ReminderDraft) async -> Bool {
    guard !isWorking else { return false }
    isWorking = true
    defer { isWorking = false }
    do {
      let now = clock()
      let reminder = try draft.reminder(now: now)
      try validateAdmission(reminder, now: now)
      try await persistDraft(reminder, expectedRevision: draft.original?.revision)
      message = nil
      await refresh()
      return true
    } catch {
      message = "Could not save. Check the fields, or reopen to review a newer version. \(error)"
      return false
    }
  }

  public var schedulingNotice: String? {
    guard let result else { return nil }
    if (result.authorization == .notDetermined || result.authorization == .denied),
      result.error == "Notification authorization is \(result.authorization.rawValue)" { return nil }
    return result.error
  }

  @discardableResult public func snooze(_ reminder: Reminder, for duration: TimeInterval) async -> Bool {
    let now = clock()
    return await snooze(reminder, until: now.addingTimeInterval(duration), now: now)
  }

  @discardableResult public func snooze(_ reminder: Reminder, until: Date) async -> Bool {
    await snooze(reminder, until: until, now: clock())
  }

  private func snooze(_ reminder: Reminder, until: Date, now: Date) async -> Bool {
    guard !isWorking else { return false }
    isWorking = true
    defer { isWorking = false }
    do {
      try saveSnooze(reminder, until: until, now: now)
      message = nil
    } catch {
      message = "Could not snooze. Please review the reminder. \(error)"
      await refresh()
      return false
    }
    await refresh()
    return true
  }

  public func dismissNotice(_ notice: ReminderNotice) async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    if recovery.dismiss(notice, now: clock()) { await refresh() }
  }

  @discardableResult public func snoozeNotice(_ notice: ReminderNotice, occurrenceAt: Date?, until: Date,
    expectedRevision: Int64) async -> Bool {
    guard !isWorking else { return false }
    isWorking = true
    defer { isWorking = false }
    let succeeded = recovery.snooze(notice, occurrenceAt: occurrenceAt, until: until,
      expectedRevision: expectedRevision, now: clock())
    if succeeded { await refresh() }
    return succeeded
  }

  @discardableResult public func saveNotificationPolicy(_ policy: NotificationPolicy, expectedRevision: Int64) async -> Bool {
    guard !isWorking else { return false }
    isWorking = true
    defer { isWorking = false }
    let succeeded = recovery.savePolicy(policy, expectedRevision: expectedRevision)
    if succeeded { await refresh() }
    return succeeded
  }

  public func enableNotifications() async {
    guard !isWorking, let requestPermission else { return }
    isWorking = true
    defer { isWorking = false }
    do { try await requestPermission(); message = nil }
    catch { message = "Notification permission request failed: \(error)" }
    await refresh()
  }

  private func find(_ id: UUID) throws -> Reminder {
    guard let item = try store.list().first(where: { $0.id == id }) else {
      throw PresentationError.reminderNotFound
    }
    return item
  }

  private func update(_ id: UUID, now: Date, change: (inout Reminder) throws -> Void) throws {
    var item = try find(id)
    let revision = item.revision
    try change(&item)
    item.updatedAt = now
    try saveValidated(item, expectedRevision: revision, now: now)
  }

  /// Reject active out-of-range alert arithmetic before it can poison recovery.
  /// A point window preserves dormant snoozed/completed candidates and does not
  /// claim to validate future delivery or quiet-hours policy. Store decoding stays
  /// permissive so existing records can still be opened and explicitly repaired.
  private func saveValidated(_ reminder: Reminder, expectedRevision: Int64?, now: Date,
    expectedPolicyRevision: Int64? = nil) throws {
    try validateAdmission(reminder, now: now)
    try store.save(reminder, expectedRevision: expectedRevision, expectedPolicyRevision: expectedPolicyRevision)
    invalidateRefresh()
  }

  private func validateAdmission(_ reminder: Reminder, now: Date) throws {
    _ = try ScheduleCalculator.plannedNotifications(for: reminder,
      now: now, horizon: now, includingStart: true)
  }

  private func persistDraft(_ reminder: Reminder, expectedRevision: Int64?) async throws {
    draftWriteInFlight = true
    invalidateRefresh()
    // End the write interval before the caller starts its follow-up refresh.
    // Failure also fences pending loads and retains the last accepted UI data.
    defer {
      draftWriteInFlight = false
      invalidateRefresh()
    }
    try await draftWriter.save(reminder, expectedRevision: expectedRevision)
  }

  /// Keep the existing target while its policy-adjusted alert is pending. A concurrent
  /// policy edit rejects the save rather than committing a target chosen from stale policy.
  private func saveSnooze(_ reminder: Reminder, until: Date, now: Date) throws {
    guard until > now else { throw CoreError.invalidDate }
    let policy = try store.notificationPolicy()
    var pendingTarget: Date?
    if let snooze = reminder.snoozedUntil {
      let delivery = policy.bypassQuietHours
        ? snooze : policy.quietHours?.nextAllowedDate(for: snooze) ?? snooze
      // Same supported Gregorian date range as Core validation, before comparing
      // a policy-derived date. No invalid effective delivery is silently accepted.
      let seconds = delivery.timeIntervalSince1970
      guard seconds.isFinite, seconds >= -62_135_596_800, seconds < 253_402_300_800 else {
        throw CoreError.invalidDate
      }
      if delivery > now { pendingTarget = reminder.snoozedOccurrenceAt ?? reminder.dueAt }
    }
    var updated = reminder
    updated.snoozedOccurrenceAt = try pendingTarget ?? reminder.occurrenceToSnooze(at: now)
    updated.snoozedUntil = until
    updated.updatedAt = now
    try saveValidated(updated, expectedRevision: reminder.revision, now: now,
      expectedPolicyRevision: policy.revision)
  }
}

public enum PresentationError: Error { case reminderNotFound, invalidAlertMinutes }

enum RefreshPublicationOutcome: Equatable, Sendable {
  case loaded(NotificationPolicy), failed, superseded
}
