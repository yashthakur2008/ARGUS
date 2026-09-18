import Foundation
import Testing
import ArgusCore
import ArgusStore
import ArgusPlatform
@testable import ArgusPresentation

@MainActor struct ReconciliationOrderingIntegrationTests {
  // Removing AppModel's requestSequence forwarding must fail this regression.
  // The application, store and reconciler are real. Only the OS notification
  // boundary is replaced, and no actor job ordering or timing assumption is used.
  @Test(arguments: [false, true])
  func refreshForwardsLogicalOrderAcrossClockChanges(clockReversed: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ReconciliationOrdering.\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReminderStore(databaseURL: directory.appendingPathComponent("fixture.sqlite"))
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let due = start.addingTimeInterval(60)
    let source = try Reminder(title: "Crossed deadline", dueAt: due, timeZoneID: "UTC",
      createdAt: start, updatedAt: start)
    try store.save(source, expectedRevision: nil)
    let earlier = start
    let later = start.addingTimeInterval(120)
    let clock = FixtureClock(clockReversed ? later : earlier)
    let client = OrderingNotifications()
    let reconciler = NotificationReconciler(store: store, client: client)
    let model = AppModel(store: store, client: client, clock: { clock.read() },
      refreshLoader: ReminderRefreshLoader(store: store), reconciler: reconciler)

    await model.refresh()
    #expect(model.result?.scheduledCount == (clockReversed ? 0 : 1))
    clock.advance(clockReversed ? -120 : 120)
    await model.refresh()
    let current = try #require(model.result)
    let expected = try store.desiredSystemNotifications(now: clock.read())
    #expect(!current.isPending)
    #expect(current.scheduledCount == (clockReversed ? 1 : 0))
    #expect(await client.currentIntents() == expected)
    #expect(model.referenceDate == clock.read())

    let operations = await client.operations
    // The second real application refresh owns sequence2. A delayed sequence1
    // must reuse that completion, rather than restore its older scheduling window.
    let obsolete = await reconciler.reconcileSystemNotifications(
      now: clockReversed ? later : earlier, requestSequence: 1)
    #expect(obsolete == current)
    #expect(await client.operations == operations)
    #expect(await client.currentIntents() == expected)
    #expect(model.result == current)
    #expect(try store.list() == [source])
  }
}

private actor OrderingNotifications: NotificationClient {
  private var intents: [String: NotificationIntent] = [:]
  private(set) var operations = 0
  func authorizationStatus() -> NotificationAuthorization {
    operations += 1
    return .authorized
  }
  func pending() -> [NotificationIntent] {
    operations += 1
    return currentIntents()
  }
  func add(_ intent: NotificationIntent) {
    operations += 1
    intents[intent.id] = intent
  }
  func remove(ids: [String]) {
    operations += 1
    for id in ids { intents.removeValue(forKey: id) }
  }
  func currentIntents() -> [NotificationIntent] {
    intents.values.sorted { $0.id < $1.id }
  }
}
