import Foundation
import Testing
import ArgusCore
@testable import ArgusStore

@Test(arguments: ["revision", "id", "zone", "json", "metadata"])
func corruptionIsVisibleAndNeverRepaired(kind: String) throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  try store.save(reminder, expectedRevision: nil)
  let database = try SQLiteDatabase(url: url)
  switch kind {
  case "revision": try database.execute("UPDATE reminders SET revision = 2")
  case "id": try database.execute("UPDATE reminders SET id = 'not-the-payload-id'")
  case "json": try database.execute("UPDATE reminders SET payload = x'00'")
  case "metadata": try database.execute("DELETE FROM store_metadata")
  default:
    var invalid = reminder
    invalid.timeZoneID = "Mars/Olympus"
    let payload = try JSONEncoder().encode(invalid)
    try database.statement("UPDATE reminders SET payload = ?") { statement in
      try database.bind(payload, to: statement, at: 1)
      _ = try database.step(statement)
    }
  }
  #expect(throws: (any Error).self) { _ = try ReminderStore(databaseURL: url) }
  #expect(try database.scalar("SELECT count(*) FROM reminders") == 1)
}

@Test func transactionRollsBackRowWhenGenerationWriteFails() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  try store.save(reminder, expectedRevision: nil)
  let database = try SQLiteDatabase(url: url)
  try database.execute("CREATE TRIGGER fail_generation BEFORE UPDATE ON store_metadata BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
  var edit = reminder
  edit.title = "Must roll back"
  #expect(throws: (any Error).self) { try store.save(edit, expectedRevision: 1) }
  #expect(throws: (any Error).self) { try store.delete(id: reminder.id, expectedRevision: 1) }
  var extra = reminder
  extra.id = UUID()
  #expect(throws: (any Error).self) { try store.save(extra, expectedRevision: nil) }
  #expect(try store.list() == [reminder])
  #expect(try store.generation() == 1)
  #expect(try ReminderStore(databaseURL: url).list() == [reminder])
}

@Test func checkedGenerationAndRevisionOverflow() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  try store.save(reminder, expectedRevision: nil)
  let database = try SQLiteDatabase(url: url)
  try database.execute("UPDATE store_metadata SET generation = 9223372036854775807")
  #expect(throws: StoreError.revisionOverflow) { try store.save(reminder, expectedRevision: 1) }
  #expect(try store.list() == [reminder])
  var maximum = reminder
  maximum.revision = Int64.max
  let payload = try JSONEncoder().encode(maximum)
  try database.statement("UPDATE reminders SET revision = 9223372036854775807, payload = ?") { statement in
    try database.bind(payload, to: statement, at: 1)
    _ = try database.step(statement)
  }
  #expect(throws: StoreError.revisionOverflow) { try store.save(maximum, expectedRevision: Int64.max) }
  #expect(try store.list() == [maximum])
}

@Test func unknownSchemaAndUnversionedTablesAreNotReset() throws {
  let (url, _) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let database = try SQLiteDatabase(url: url)
  try database.execute("PRAGMA user_version = 2")
  #expect(throws: StoreError.unsupportedSchema(2)) { _ = try ReminderStore(databaseURL: url) }
  try database.execute("PRAGMA user_version = 0")
  #expect(throws: (any Error).self) { _ = try ReminderStore(databaseURL: url) }
  #expect(try database.scalar("SELECT count(*) FROM store_metadata") == 1)
}

@Test func concurrentConnectionsHaveExactlyOneOptimisticWinner() async throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let first = try ReminderStore(databaseURL: url)
  let second = try ReminderStore(databaseURL: url)
  try first.save(reminder, expectedRevision: nil)
  let winners = try await withThrowingTaskGroup(of: Int.self) { group in
    for store in [first, second] {
      group.addTask {
        do { try store.save(reminder, expectedRevision: 1); return 1 }
        catch StoreError.conflict { return 0 }
      }
    }
    var count = 0
    for try await winner in group { count += winner }
    return count
  }
  #expect(winners == 1)
  #expect(try first.list().first?.revision == 2)
  #expect(try second.generation() == 2)
}

@Test func embeddedNULMetadataIDCannotMasqueradeAsPayloadID() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  try store.save(reminder, expectedRevision: nil)
  let database = try SQLiteDatabase(url: url)
  try database.execute("UPDATE reminders SET id = id || char(0) || 'corrupt'")
  #expect(throws: (any Error).self) { _ = try store.list() }
  #expect(throws: (any Error).self) { _ = try ReminderStore(databaseURL: url) }
}

@Test(arguments: [Int64(0), Int64(2)])
func rejectedSchemaDoesNotChangeDatabaseBytes(version: Int64) throws {
  let (url, _) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let database = try SQLiteDatabase(url: url)
  try database.execute("PRAGMA journal_mode = DELETE")
  try database.execute("PRAGMA user_version = \(version)")
  let before = try Data(contentsOf: url)
  #expect(throws: (any Error).self) { _ = try ReminderStore(databaseURL: url) }
  #expect(try Data(contentsOf: url) == before)
}
