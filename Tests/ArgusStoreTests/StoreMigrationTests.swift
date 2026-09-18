import Foundation
import Testing
import CSQLite
import ArgusCore
@testable import ArgusStore

func createVersionOne(_ url: URL, reminder: Reminder, extraSQL: String = "", corruptPayload: Bool = false) throws {
  var handle: OpaquePointer?
  guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { throw StoreError.corruption("Fixture open failed") }
  defer { sqlite3_close(handle) }
  let payload = corruptPayload ? Data([0]) : try JSONEncoder().encode(reminder)
  let hex = payload.map { String(format: "%02x", $0) }.joined()
  let sql = """
    CREATE TABLE reminders (id TEXT PRIMARY KEY NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), payload BLOB NOT NULL);
    CREATE TABLE store_metadata (id INTEGER PRIMARY KEY CHECK(id = 1), generation INTEGER NOT NULL CHECK(generation >= 0));
    INSERT INTO store_metadata VALUES (1, 17);
    INSERT INTO reminders VALUES ('\(reminder.id.uuidString)', \(reminder.revision), x'\(hex)');
    PRAGMA user_version = 1;
    \(extraSQL)
    """
  guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.corruption("Fixture SQL failed") }
}

func rawScalar(_ url: URL, _ sql: String) throws -> Int64 {
  var handle: OpaquePointer?
  guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { throw StoreError.corruption("Fixture open failed") }
  defer { sqlite3_close(handle) }
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw StoreError.corruption("Fixture prepare failed") }
  defer { sqlite3_finalize(statement) }
  guard sqlite3_step(statement) == SQLITE_ROW else { throw StoreError.corruption("Fixture read failed") }
  return sqlite3_column_int64(statement, 0)
}

@Test func recoveryVersionOneMigratesPreservingRecordsAndGeneration() throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  var reminder = original
  reminder.revision = 7
  try createVersionOne(url, reminder: reminder)
  let store = try ReminderStore(databaseURL: url)
  #expect(try store.list() == [reminder])
  #expect(try store.generation() == 17)
  #expect(try store.notificationPolicy() == NotificationPolicy())
  #expect(try rawScalar(url, "PRAGMA user_version") == 2)
  #expect(try rawScalar(url, "SELECT count(*) FROM reminder_notices") == 0)
}

@Test func recoveryMigrationFailureRollsBackAllNewTablesAndVersion() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  try createVersionOne(url, reminder: reminder, extraSQL: "CREATE TABLE fixture_blocker (id INTEGER); CREATE INDEX reminder_notices_active ON fixture_blocker(id);")
  #expect(throws: (any Error).self) { _ = try ReminderStore(databaseURL: url) }
  #expect(try rawScalar(url, "PRAGMA user_version") == 1)
  #expect(try rawScalar(url, "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name IN ('notification_policy', 'reminder_notices')") == 0)
  #expect(try rawScalar(url, "SELECT generation FROM store_metadata") == 17)
}

@Test func recoveryCorruptVersionOneFailsBeforeChangingBytes() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  try createVersionOne(url, reminder: reminder, corruptPayload: true)
  let before = try Data(contentsOf: url)
  #expect(throws: (any Error).self) { _ = try ReminderStore(databaseURL: url) }
  #expect(try Data(contentsOf: url) == before)
  #expect(try rawScalar(url, "PRAGMA user_version") == 1)
}

@Test(arguments: 0..<20)
func recoveryConcurrentMigrationAndWritersPreserveOptimism(_ iteration: Int) async throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  try createVersionOne(url, reminder: reminder)
  let start = MigrationStartGate()
  let wins = try await withThrowingTaskGroup(of: Int.self) { group in
    for _ in 0..<2 {
      group.addTask {
        await start.wait()
        let store = try ReminderStore(databaseURL: url)
        do { try store.save(reminder, expectedRevision: 1); return 1 }
        catch StoreError.conflict { return 0 }
      }
    }
    var count = 0
    for try await result in group { count += result }
    return count
  }
  #expect(wins == 1)
  #expect(try rawScalar(url, "PRAGMA user_version") == 2)
  #expect(try ReminderStore(databaseURL: url).generation() == 18)
}

// Release both openers together without blocking Swift's cooperative executor.
private actor MigrationStartGate {
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
      if waiters.count == 2 {
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
      }
    }
  }
}

@Test(arguments: 0..<20)
func recoveryConcurrentFreshDatabaseOpens(_ iteration: Int) async throws {
  let (url, _) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let start = MigrationStartGate()
  try await withThrowingTaskGroup(of: Void.self) { group in
    for _ in 0..<2 {
      group.addTask {
        await start.wait()
        let store = try ReminderStore(databaseURL: url)
        #expect(try store.list().isEmpty)
        #expect(try store.generation() == 0)
      }
    }
    try await group.waitForAll()
  }
  #expect(try rawScalar(url, "PRAGMA user_version") == 2)
}

@Test func recoveryWALTransitionWaitsForWriterAndPreservesMigration() async throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  try createVersionOne(url, reminder: reminder)
  var writer: OpaquePointer?
  #expect(sqlite3_open(url.path, &writer) == SQLITE_OK)
  defer { sqlite3_close(writer) }
  #expect(sqlite3_exec(writer, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
  defer { sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) }
  try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
      // SQLite's bounded startup wait blocks a thread. Do not occupy the
      // cooperative executor that must resume the writer's timed rollback.
      let store: ReminderStore = try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
          do { continuation.resume(returning: try ReminderStore(databaseURL: url)) }
          catch { continuation.resume(throwing: error) }
        }
      }
      #expect(try store.list() == [reminder])
      #expect(try store.generation() == 17)
    }
    try await Task.sleep(for: .milliseconds(150))
    #expect(sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
    try await group.waitForAll()
  }
  #expect(try rawScalar(url, "PRAGMA user_version") == 2)
  #expect(try rawScalar(url, "SELECT journal_mode = 'wal' FROM pragma_journal_mode") == 1)
}

@Test func recoveryWALTransitionExhaustionLeavesSchemaAndBytesUnchanged() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  try createVersionOne(url, reminder: reminder)
  let before = try Data(contentsOf: url)
  var writer: OpaquePointer?
  #expect(sqlite3_open(url.path, &writer) == SQLITE_OK)
  defer { sqlite3_close(writer) }
  #expect(sqlite3_exec(writer, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
  defer { sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) }
  let clock = ContinuousClock()
  let start = clock.now
  do {
    _ = try ReminderStore(databaseURL: url)
    Issue.record("Opening under a held rollback-journal writer must fail")
  } catch StoreError.sqlite(let code, _) {
    #expect(code == SQLITE_BUSY)
  }
  let elapsed = start.duration(to: clock.now)
  #expect(elapsed >= .milliseconds(150))
  #expect(elapsed < .seconds(5))
  #expect(try Data(contentsOf: url) == before)
  #expect(sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
  #expect(try rawScalar(url, "PRAGMA user_version") == 1)
  #expect(try rawScalar(url, "SELECT journal_mode = 'delete' FROM pragma_journal_mode") == 1)
  #expect(try rawScalar(url, "SELECT count(*) FROM sqlite_master WHERE name = 'notification_policy'") == 0)
  #expect(try ReminderStore(databaseURL: url).generation() == 17)
}
