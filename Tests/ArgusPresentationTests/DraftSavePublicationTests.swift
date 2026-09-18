import Foundation
import Testing
import ArgusCore
import ArgusStore
@testable import ArgusPresentation

@MainActor struct DraftSavePublicationTests {
  @Test(arguments: [false, true], [false, true])
  func saveFencesOldLoadsAndDefinesFailureState(oldLoadFails: Bool, writeConflicts: Bool) async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.dir) }
    let initial = try f.store.refreshSnapshot(now: f.now)
    let baseline = Task { await f.model.refreshOutcome() }
    await f.reader.waitForLoads(1)
    await f.reader.complete(0, with: loaded(initial))
    #expect(await baseline.value == .loaded(initial.policy))
    #expect(f.model.result != nil)
    let older = Task { await f.model.refreshOutcome() }
    await f.reader.waitForLoads(2)
    var draft = ReminderDraft(original: f.item, now: f.now, timeZone: TimeZone(identifier: "UTC")!)
    draft.title = "Draft mutation"
    let save = Task { await f.model.save(draft) }
    await f.writer.waitUntilEntered()
    #expect(f.model.isWorking)
    #expect(await f.model.refreshOutcome() == .superseded)
    #expect(await f.reader.count == 2)
    #expect(!(await f.model.save(draft))) // Busy repeat must not dispatch a second write.
    #expect(await f.writer.count == 1)
    await f.reader.complete(1, with: oldLoadFails ? .listFailure("old loader error") : loaded(initial))
    #expect(await older.value == .superseded)
    #expect(f.model.reminders == initial.reminders)
    #expect(f.model.message == nil)
    #expect(f.model.result == nil)
    #expect(!f.model.isReconciling)

    var expected = f.item
    if writeConflicts {
      let secondConnection = try ReminderStore(databaseURL: f.dir.appendingPathComponent("test.sqlite"))
      expected.title = "Changed by another connection"
      try secondConnection.save(expected, expectedRevision: 1)
    }
    let generationBeforeRelease = try f.store.generation()
    await f.writer.release()
    if writeConflicts {
      #expect(!(await save.value))
      #expect(f.model.message?.contains("Could not save") == true)
      #expect(f.model.result == nil)
      #expect(!f.model.isWorking)
      #expect(!f.model.isReconciling)
      #expect(f.model.reminders == initial.reminders) // Last accepted data, not a fake reload.
      #expect(f.model.recovery.notices == initial.notices)
      #expect(f.model.recovery.policy == initial.policy)
      #expect(try f.store.generation() == generationBeforeRelease)
      expected.revision = 2
      #expect(try f.store.reminder(id: f.item.id) == expected)
      // A later explicit refresh is not permanently suppressed by the failed write.
      let retried = Task { await f.model.refreshOutcome() }
      await f.reader.waitForLoads(3)
      let current = try f.store.refreshSnapshot(now: f.now)
      await f.reader.complete(2, with: loaded(current))
      #expect(await retried.value == .loaded(current.policy))
    } else {
      // The in-flight flag must clear before save's own follow-up refresh starts.
      await f.reader.waitForLoads(3)
      let current = try f.store.refreshSnapshot(now: f.now)
      await f.reader.complete(2, with: loaded(current))
      #expect(await save.value)
      #expect(f.model.message == nil)
      #expect(try f.store.generation() == generationBeforeRelease + 1)
      let saved = try #require(try f.store.reminder(id: f.item.id))
      #expect(saved.title == draft.title)
      #expect(saved.revision == 2)
      #expect(saved.createdAt == f.item.createdAt)
    }
    #expect(try f.store.reminder(id: f.neighbor.id) == f.neighbor)
    #expect(f.model.result != nil)
    #expect(!f.model.isWorking)
    #expect(!f.model.isReconciling)
  }

  @Test func committedSaveReturnsTrueWhenFollowupLoadFails() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.dir) }
    var draft = ReminderDraft(original: f.item, now: f.now, timeZone: TimeZone(identifier: "UTC")!)
    draft.title = "Committed despite reload error"
    let save = Task { await f.model.save(draft) }
    await f.writer.waitUntilEntered()
    await f.writer.release()
    await f.reader.waitForLoads(1)
    await f.reader.complete(0, with: .listFailure("follow-up read failed"))
    #expect(await save.value)
    #expect(try f.store.reminder(id: f.item.id)?.title == draft.title)
    #expect(try f.store.generation() == 3)
    #expect(f.model.message?.contains("Could not read reminders") == true)
    #expect(f.model.result == nil)
    #expect(!f.model.isWorking)
    #expect(!f.model.isReconciling)
  }

  @Test(arguments: [false, true], [false, true])
  func olderLoadCannotOverwriteFinishedSave(oldLoadFails: Bool, writeConflicts: Bool) async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.dir) }
    let initial = try f.store.refreshSnapshot(now: f.now)
    let older = Task { await f.model.refreshOutcome() }
    await f.reader.waitForLoads(1)
    var draft = ReminderDraft(original: f.item, now: f.now, timeZone: TimeZone(identifier: "UTC")!)
    draft.title = "Finished save"
    let save = Task { await f.model.save(draft) }
    await f.writer.waitUntilEntered()
    if writeConflicts {
      var changed = f.item
      changed.title = "External edit"
      try f.store.save(changed, expectedRevision: 1)
    }
    await f.writer.release()
    if !writeConflicts {
      await f.reader.waitForLoads(2)
      await f.reader.complete(1, with: loaded(try f.store.refreshSnapshot(now: f.now)))
    }
    #expect(await save.value == !writeConflicts)
    let acceptedReminders = f.model.reminders
    let acceptedMessage = f.model.message
    let hadResult = f.model.result != nil
    await f.reader.complete(0, with: oldLoadFails ? .listFailure("obsolete failure") : loaded(initial))
    #expect(await older.value == .superseded)
    #expect(f.model.reminders == acceptedReminders)
    #expect(f.model.message == acceptedMessage)
    #expect((f.model.result != nil) == hadResult)
    #expect(!f.model.isWorking)
    #expect(!f.model.isReconciling)
  }

  @Test func invalidCandidateNeverDispatchesWriter() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.dir) }
    var draft = ReminderDraft(original: f.item, now: f.now, timeZone: TimeZone(identifier: "UTC")!)
    draft.alertMinutes = "1000000000000"
    let before = try f.store.list()
    #expect(!(await f.model.save(draft)))
    #expect(await f.writer.count == 0)
    #expect(await f.reader.count == 0)
    #expect(try f.store.list() == before)
    #expect(try f.store.generation() == 2)
    #expect(!f.model.isWorking)
  }

  private func loaded(_ s: ReminderRefreshSnapshot) -> ReminderRefreshLoadResult {
    .loaded(reminders: s.reminders, notices: s.notices, policy: s.policy)
  }
  private func fixture() throws -> (model: AppModel, store: ReminderStore, item: Reminder,
    neighbor: Reminder, reader: DraftReadGate, writer: DraftWriteGate, dir: URL, now: Date) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try ReminderStore(databaseURL: dir.appendingPathComponent("test.sqlite"))
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let item = try Reminder(title: "Original", dueAt: now.addingTimeInterval(600), timeZoneID: "UTC", createdAt: now, updatedAt: now)
    let neighbor = try Reminder(title: "Neighbor", dueAt: now.addingTimeInterval(1200), timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try store.save(item, expectedRevision: nil)
    try store.save(neighbor, expectedRevision: nil)
    let reader = DraftReadGate()
    let writer = DraftWriteGate(store: store)
    let model = AppModel(store: store, client: FakeNotifications(), clock: { now }, refreshLoader: reader, draftWriter: writer)
    return (model, store, item, neighbor, reader, writer, dir, now)
  }
}

private actor DraftWriteGate: ReminderDraftWriting {
  let store: ReminderStore
  private(set) var count = 0
  private var entered: CheckedContinuation<Void, Never>?
  private var permission: CheckedContinuation<Void, Never>?
  init(store: ReminderStore) { self.store = store }
  func save(_ reminder: Reminder, expectedRevision: Int64?) async throws {
    count += 1
    await withCheckedContinuation { continuation in
      permission = continuation
      entered?.resume()
      entered = nil
    }
    try store.save(reminder, expectedRevision: expectedRevision)
  }
  func waitUntilEntered() async {
    if count > 0 { return }
    await withCheckedContinuation { entered = $0 }
  }
  func release() { permission?.resume(); permission = nil }
}

private actor DraftReadGate: ReminderRefreshLoading {
  private(set) var count = 0
  private var pending: [Int: CheckedContinuation<ReminderRefreshLoadResult, Never>] = [:]
  private var observer: (Int, CheckedContinuation<Void, Never>)?
  func load(now: Date, sequence: Int) async -> ReminderRefreshLoadResult {
    let id = count
    count += 1
    return await withCheckedContinuation { continuation in
      pending[id] = continuation
      if let observer, count >= observer.0 { self.observer = nil; observer.1.resume() }
    }
  }
  func waitForLoads(_ expected: Int) async {
    if count >= expected { return }
    await withCheckedContinuation { observer = (expected, $0) }
  }
  func complete(_ id: Int, with result: ReminderRefreshLoadResult) { pending.removeValue(forKey: id)?.resume(returning: result) }
}
