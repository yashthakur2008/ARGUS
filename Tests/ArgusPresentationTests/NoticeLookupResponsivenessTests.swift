import Foundation
import Testing
import ArgusCore
@testable import ArgusStore
@testable import ArgusPresentation

// Synthetic same-store NSLock boundary, not an actual refresh benchmark.
// Behavioral red used an adapter delegating to the existing synchronous open.
@MainActor struct NoticeLookupResponsivenessTests {
  @Test func sourceLookupYieldsWhileSameStoreLockIsHeld() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReminderStore(databaseURL: directory.appendingPathComponent("lookup.sqlite"))
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let source = try Reminder(title: "Source", dueAt: now.addingTimeInterval(-60), timeZoneID: "UTC",
      createdAt: now.addingTimeInterval(-120), updatedAt: now)
    try store.save(source, expectedRevision: nil)
    _ = try store.captureDueNotices(now: now)
    let notice = try #require(try store.notices().first)
    let recovery = ReminderRecoveryModel(store: store)
    let entered = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    let holder = Task.detached {
      store.lock.withLock {
        entered.continuation.yield(())
        entered.continuation.finish()
        // Bound the intentionally broken implementation's wait. This is a
        // deadlock watchdog, not a millisecond performance acceptance threshold.
        return release.wait(timeout: .now() + 2) == .success
      }
    }
    for await _ in entered.stream { break }
    let heartbeat = Task { @MainActor in _ = release.signal() }
    let result = await recovery.lookupSource(notice)
    await heartbeat.value
    #expect(await holder.value)
    #expect(result == .found(source))
    #expect(recovery.issue == nil)
  }
}

