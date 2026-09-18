import Foundation
import Testing
import ArgusCore
@testable import ArgusStore
@testable import ArgusPresentation

extension RecoveryModelTests {
  @Test func asyncLookupResultsNeverReplaceUnrelatedRecoveryIssue() async throws {
    let (model, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let item = try source(model)
    await model.refresh()
    let notice = try #require(model.recovery.activeNotices.first)
    // Produce a real unrelated issue without changing the stored source.
    #expect(!model.recovery.snooze(notice, occurrenceAt: now, until: now.addingTimeInterval(600),
      expectedRevision: 1, now: now))
    let priorIssue = try #require(model.recovery.issue)
    #expect(await model.recovery.lookupSource(notice) == .found(item))
    #expect(model.recovery.issue == priorIssue)
    // Corrupt only this disposable fixture to exercise the real reader's failure path.
    try model.store.lock.withLock {
      try model.store.database.execute("UPDATE reminders SET payload = x'00'")
    }
    let failed = await model.recovery.lookupSource(notice)
    if case .failed(let message) = failed { #expect(message.contains("Could not open")) }
    else { Issue.record("Expected request-scoped read failure") }
    #expect(model.recovery.issue == priorIssue)
    try model.store.lock.withLock { try model.store.database.execute("DELETE FROM reminders") }
    #expect(await model.recovery.lookupSource(notice) == .missing)
    #expect(model.recovery.issue == priorIssue)
    // Compatibility API intentionally retains its original shared-issue semantics.
    #expect(model.recovery.open(notice) == nil)
    #expect(model.recovery.issue?.contains("no longer exists") == true)
  }
}
