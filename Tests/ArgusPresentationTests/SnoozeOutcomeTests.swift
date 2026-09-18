import Foundation
import Testing
import ArgusCore
import ArgusStore
@testable import ArgusPresentation

extension AppModelTests {
  @Test(arguments: ["success", "expired", "stale"])
  func snoozeReportsWhetherEditorMayDismiss(scenario: String) async throws {
    let (model, dir) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    var item = try Reminder(title: "Snooze fixture", dueAt: now, timeZoneID: "UTC",
      createdAt: now, updatedAt: now)
    try model.store.save(item, expectedRevision: nil)
    if scenario == "stale" {
      item.title = "Changed elsewhere"
      try model.store.save(item, expectedRevision: 1)
    }
    let before = try model.store.list()
    let until = now.addingTimeInterval(scenario == "expired" ? -1 : 600)
    let outcome = await model.snooze(item, until: until)
    #expect(outcome == (scenario == "success"))
    if scenario == "success" {
      let saved = try #require(try model.store.reminder(id: item.id))
      #expect(saved.snoozedUntil == until)
      #expect(model.message == nil)
    } else {
      #expect(try model.store.list() == before)
      #expect(model.message?.contains("Could not snooze") == true)
    }
    #expect(!model.isWorking)
  }

  @Test func relativeSnoozeReportsSuccessfulPersistence() async throws {
    let (model, dir) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let item = try Reminder(title: "Relative snooze fixture", dueAt: now, timeZoneID: "UTC",
      createdAt: now, updatedAt: now)
    try model.store.save(item, expectedRevision: nil)
    let outcome = await model.snooze(item, for: 600)
    #expect(outcome)
    #expect(try model.store.reminder(id: item.id)?.snoozedUntil == now.addingTimeInterval(600))
  }
}

extension AppModelTests {
  @Test func busyModelDoesNotReportSnoozeSuccess() async throws {
    let (fixture, dir) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let gate = SnoozePermissionGate()
    let now = self.now
    let model = AppModel(store: fixture.store, client: FakeNotifications(), clock: { now },
      requestPermission: { await gate.request() })
    let item = try Reminder(title: "Busy fixture", dueAt: now, timeZoneID: "UTC",
      createdAt: now, updatedAt: now)
    try model.store.save(item, expectedRevision: nil)
    let pending = Task { await model.enableNotifications() }
    await gate.waitUntilEntered()
    #expect(model.isWorking)
    #expect(!(await model.snooze(item, until: now.addingTimeInterval(600))))
    #expect(try model.store.list() == [item])
    await gate.release()
    await pending.value
    #expect(!model.isWorking)
  }
}

private actor SnoozePermissionGate {
  private var entered = false
  private var entryWaiter: CheckedContinuation<Void, Never>?
  private var permission: CheckedContinuation<Void, Never>?
  func request() async {
    await withCheckedContinuation { continuation in
      permission = continuation
      entered = true
      entryWaiter?.resume()
      entryWaiter = nil
    }
  }
  func waitUntilEntered() async {
    if !entered { await withCheckedContinuation { entryWaiter = $0 } }
  }
  func release() { permission?.resume(); permission = nil }
}
