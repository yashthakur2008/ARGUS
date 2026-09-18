import Foundation
import Testing
import ArgusCore
import ArgusStore
@testable import ArgusPresentation

// Model-window proof, not a native UI regression. These tests are expected to
// pass before the view-only fix: persistence commits before refresh returns.
@MainActor struct EditorSubmissionWindowTests {
  @Test(arguments: ["policy", "snooze", "notice"], [false, true])
  func committedSubmissionRemainsBusyUntilRefreshCompletes(kind: String, refreshFails: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReminderStore(databaseURL: directory.appendingPathComponent("fixture.sqlite"))
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let item = try Reminder(title: "Submission", dueAt: now, timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try store.save(item, expectedRevision: nil)
    _ = try store.captureDueNotices(now: now)
    let notice = try #require(try store.notices().first)
    let gate = EditorRefreshGate()
    let model = AppModel(store: store, client: FakeNotifications(), clock: { now }, refreshLoader: gate)
    let until = now.addingTimeInterval(600)
    let policy = try NotificationPolicy(bypassQuietHours: true)
    let completion = SubmissionCompletion()
    func submit() async -> Bool {
      switch kind {
      case "policy": return await model.saveNotificationPolicy(policy, expectedRevision: 1)
      case "snooze": return await model.snooze(item, until: until)
      default: return await model.snoozeNotice(notice, occurrenceAt: item.dueAt, until: until, expectedRevision: 1)
      }
    }
    let pending = Task { let result = await submit(); completion.finished = true; return result }
    await gate.waitUntilEntered()
    #expect(model.isWorking)
    #expect(!completion.finished)
    if kind == "policy" {
      #expect(try store.notificationPolicy().bypassQuietHours)
      #expect(try store.notificationPolicy().revision == 2)
    } else {
      let saved = try #require(try store.reminder(id: item.id))
      #expect(saved.snoozedUntil == until)
      #expect(saved.snoozedOccurrenceAt == item.dueAt)
      #expect(saved.revision == 2)
      if kind == "notice" { #expect(try store.notices().isEmpty) }
    }
    let generation = try store.generation()
    let duplicate = await submit()
    #expect(!duplicate)
    #expect(try store.generation() == generation)
    #expect(await gate.count == 1)
    let snapshot = try store.refreshSnapshot(now: now)
    await gate.finish(refreshFails ? .listFailure("synthetic follow-up failure")
      : .loaded(reminders: snapshot.reminders, notices: snapshot.notices, policy: snapshot.policy))
    #expect(await pending.value) // Success reports the committed write, not refresh health.
    #expect(completion.finished)
    #expect(!model.isWorking)
    #expect(try store.generation() == generation)
    if refreshFails { #expect(model.message?.contains("Could not read reminders") == true) }
  }
}

@MainActor private final class SubmissionCompletion { var finished = false }
private actor EditorRefreshGate: ReminderRefreshLoading {
  private(set) var count = 0
  private var pending: CheckedContinuation<ReminderRefreshLoadResult, Never>?
  private var waiter: CheckedContinuation<Void, Never>?
  func load(now: Date, sequence: Int) async -> ReminderRefreshLoadResult {
    count += 1
    return await withCheckedContinuation { pending = $0; waiter?.resume(); waiter = nil }
  }
  func waitUntilEntered() async {
    if pending != nil { return }
    await withCheckedContinuation { waiter = $0 }
  }
  func finish(_ result: ReminderRefreshLoadResult) { pending?.resume(returning: result); pending = nil }
}
