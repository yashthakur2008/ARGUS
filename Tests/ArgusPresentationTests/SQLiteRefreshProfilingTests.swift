import Foundation
import Testing
import CSQLite
import ArgusCore
import ArgusStore
import ArgusPlatform
import ArgusPresentation

/// Opt-in diagnostics, not timing gates. No OS notification adapter is constructed.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ARGUS_SQLITE_PROFILE"] == "1"))
@MainActor struct SQLiteRefreshProfilingTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func heldWriterBlocksRefreshHeartbeat() async throws {
    let fixture = try ProfileFixture()
    defer { fixture.cleanUp() }
    let store = fixture.store
    let instant = now
    let model = AppModel(store: store, client: ProfileNotifications(), clock: { instant })
    await model.refresh()
    #expect(model.message == nil)
    let controlStart = ContinuousClock.now
    let controlBeat = Task { @MainActor in ContinuousClock.now }
    await model.refresh()
    let controlEnd = ContinuousClock.now
    let controlHeartbeat = await controlBeat.value
    print("SQLITE_PROFILE unlocked_empty refresh_ms=\(milliseconds(controlStart.duration(to: controlEnd))) queued_heartbeat_ms=\(milliseconds(controlStart.duration(to: controlHeartbeat)))")
    try fixture.execute("BEGIN IMMEDIATE")
    defer { try? fixture.execute("ROLLBACK") }
    // WAL readers still work. Capture, not list(), needs the writer lock.
    #expect(try store.list().isEmpty)
    let clock = ContinuousClock()
    let start = clock.now
    let heartbeat = Task { @MainActor in clock.now }
    await model.refresh()
    let finished = clock.now
    let beat = await heartbeat.value
    print("SQLITE_PROFILE held_writer refresh_ms=\(milliseconds(start.duration(to: finished))) queued_heartbeat_ms=\(milliseconds(start.duration(to: beat)))")
    #expect(model.message?.contains("database is locked") == true)
    #expect(model.result == nil)
    #expect(!model.isReconciling)
    #expect(model.noticesUnavailableMessage != nil)
    #expect(try store.generation() == 0)
    try fixture.execute("ROLLBACK")
    await model.refresh()
    #expect(model.message == nil)
    #expect(model.noticesUnavailableMessage == nil)
    #expect(model.result?.authorization == .denied)
  }

  @Test func boundedHistoryGrowth() async throws {
    for count in [100, 1_000] {
      let fixture = try ProfileFixture()
      defer { fixture.cleanUp() }
      let store = fixture.store
      // One fixture transaction, not N production FULL-sync commits. Production
      // Codable reminders and production notice capture provide valid payloads.
      try fixture.seedReminders(count: count, now: now)
      #expect(try store.list().count == count)
      #expect(try store.generation() == Int64(count))
      let captureStart = ContinuousClock.now
      let first = try store.captureDueNotices(now: now)
      print("SQLITE_PROFILE rows=\(count) first_capture_ms=\(milliseconds(captureStart.duration(to: .now)))")
      #expect(first.insertedCount == count)
      let instant = now
      let model = AppModel(store: store, client: ProfileNotifications(), clock: { instant })
      for dismissed in [false, true] {
        if dismissed {
          // Exercise public dismissal once, then batch the equivalent fixture-only
          // column update to avoid 1,000 unrelated durable per-row commits.
          let notice = try #require(store.notices().first)
          try store.dismissNotice(id: notice.id, now: now)
          try fixture.execute("UPDATE reminder_notices SET dismissed_at = \(now.timeIntervalSinceReferenceDate)")
        }
        await model.refresh() // warm caches, excluded from the samples
        var list: [Double] = [], capture: [Double] = [], history: [Double] = []
        var recovery: [Double] = [], refresh: [Double] = [], heartbeat: [Double] = []
        for _ in 0..<7 {
          list.append(try time {
            let loaded = try store.list()
            #expect(loaded.count == count)
          })
          capture.append(try time {
            let result = try store.captureDueNotices(now: now)
            #expect(result.insertedCount == 0)
            #expect(result.activeCount == (dismissed ? 0 : count))
          })
          history.append(try time {
            let loaded = try store.notices(includeDismissed: true)
            #expect(loaded.count == count)
          })
          recovery.append(try time { try model.recovery.refresh(now: now) })
          let clock = ContinuousClock()
          let start = clock.now
          let beat = Task { @MainActor in clock.now }
          await model.refresh()
          refresh.append(milliseconds(start.duration(to: clock.now)))
          heartbeat.append(milliseconds(start.duration(to: await beat.value)))
          #expect(model.reminders.count == count)
          #expect(model.recovery.notices.count == count)
          #expect(model.message == nil)
          #expect(model.result?.authorization == .denied)
        }
        #expect(try store.notices().count == (dismissed ? 0 : count))
        print("SQLITE_PROFILE rows=\(count) dismissed=\(dismissed) samples=7 " +
          "list=\(summary(list)) capture_noop=\(summary(capture)) history=\(summary(history)) " +
          "recovery=\(summary(recovery)) refresh=\(summary(refresh)) queued_heartbeat=\(summary(heartbeat))")
      }
    }
  }

  private func time(_ operation: () throws -> Void) rethrows -> Double {
    let start = ContinuousClock.now
    try operation()
    return milliseconds(start.duration(to: .now))
  }

  private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
  }

  private func summary(_ values: [Double]) -> String {
    let sorted = values.sorted()
    return String(format: "%.3f/%.3f/%.3fms(min/median/max)", sorted[0], sorted[sorted.count / 2], sorted[sorted.count - 1])
  }
}

private actor ProfileNotifications: NotificationClient {
  func authorizationStatus() async -> NotificationAuthorization { .denied }
  func pending() async throws -> [NotificationIntent] { [] }
  func add(_ intent: NotificationIntent) async throws {}
  func remove(ids: [String]) async {}
}

/// Raw SQL is restricted to disposable fixture setup and writer-lock injection.
/// All timed operations use the public production API, without testable imports.
@MainActor private final class ProfileFixture {
  let directory: URL
  let store: ReminderStore
  private var database: OpaquePointer?

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("argus-profile-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("profile.sqlite")
    store = try ReminderStore(databaseURL: url)
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
      sqlite3_close(database)
      database = nil
      throw StoreError.corruption("Cannot open disposable fixture")
    }
  }

  func cleanUp() {
    sqlite3_close(database)
    database = nil
    try? FileManager.default.removeItem(at: directory)
  }

  func execute(_ sql: String) throws {
    let code = sqlite3_exec(database, sql, nil, nil, nil)
    guard code == SQLITE_OK else {
      throw StoreError.sqlite(code: code, message: String(cString: sqlite3_errmsg(database)))
    }
  }

  func seedReminders(count: Int, now: Date) throws {
    try execute("PRAGMA foreign_keys = ON")
    try execute("BEGIN IMMEDIATE")
    do {
      for index in 0..<count {
        let reminder = try Reminder(title: "Profile \(index)", dueAt: now.addingTimeInterval(-60),
          timeZoneID: "UTC", createdAt: now.addingTimeInterval(-120), updatedAt: now.addingTimeInterval(-120))
        let hex = try JSONEncoder().encode(reminder).map { String(format: "%02x", $0) }.joined()
        try execute("INSERT INTO reminders (id, revision, payload) VALUES ('\(reminder.id.uuidString)', \(reminder.revision), x'\(hex)')")
      }
      try execute("UPDATE store_metadata SET generation = \(count) WHERE id = 1")
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
}
