# ARGUS reminders implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task-by-task. Record red/green tests and scoped commits.

**Goal:** Deliver the first executable vertical slice: typed local reminders, durable SQLite state, a native Today screen, and a macOS notification adapter with honest permission/recovery status.

**Architecture:** One root Swift package with ArgusCore, ArgusStore, ArgusPlatform, and ArgusApp targets. No cloud backend or third-party dependency. The core is platform-independent Foundation code; SQLite, UserNotifications and SwiftUI live in separate targets.

**Tech Stack:** Swift 6.1.2, bundled Swift Testing, macOS 14+, system SQLite, SwiftUI, UserNotifications. The installed Command Line Tools SwiftPM has a verified llbuild ABI mismatch and its compiler sees duplicate SwiftBridging module maps. A verified Apple-notarized official Swift 6.1.2 package was downloaded and extracted only into agent scratch, without installation or global toolchain changes, to run real builds/tests. This is development tooling, not an ARGUS runtime dependency.

**Spec:** ../specs/2026-09-17-argus-native-macos-design.md

## Global constraints and execution ruling

- No runtime language model, hosted service, shell execution from application input, or network request.
- macOS 14 minimum, Apple Silicon development verification only.
- No actual personal reminder creation, notification permission change, live voice request, account operation, global toolchain change, or App Store publication without the appropriate user/system action.
- Use temporary fixture databases for tests, never live user data.
- User approved the native direction/workflows and expressly requested swarm completion, then instructed continuation without waiting. Proceed with reversible first-slice implementation rather than asking for the same direction again. The written specification has not received a separate line-by-line user review. Release, paid-service, credential and destructive-action gates remain intact.
- Ruling: use one root Swift package rather than a nested package plus handwritten Xcode project initially. This minimizes build plumbing and permits real compilation with available Command Line Tools. A development .app bundle is not an App Store archive. Full Xcode/signing remains necessary for the release gates.
- Ruling: no worktrees. The agent harness explicitly coordinates the shared repo. Separate file ownership prevents collisions. Use branch `feat/reminders-slice` rather than mixing application implementation with main.

## Contract

Core public types must be Codable, Equatable and Sendable where applicable. Use Date UTC instants plus validated IANA `timeZoneID`. All parsing APIs take injected `now` and `TimeZone`. Never read Date() deep inside domain calculation.

`Reminder` owns UUID `id`, trimmed nonempty `title`, Date `dueAt`, String `timeZoneID`, Date `createdAt`, Date `updatedAt`, Int64 `revision`, [TimeInterval] `alertOffsets`, optional `RecurrenceRule recurrence`, optional Date `snoozedUntil`, and Bool `isCompleted`. Default offsets [0], revision 1, completion false. Provide a throwing validating initializer and `validate() throws`; mutable updates must revalidate before storage. Reject bad zones, empty/overlong titles (512 characters), nonfinite timestamps/offsets, negative offsets, more than 8 offsets, and invalid recurrence time components. Normalize duplicate offsets.

`RecurrenceRule.weekdays(hour: Int, minute: Int)` is the first supported recurrence. More recurrence grammars must fail clearly rather than silently approximate.

`ReminderCommand` cases: `create(title: String, dueAt: Date, timeZoneID: String, recurrence: RecurrenceRule?)`, `list`, `delete(id: UUID)`, `snooze(id: UUID, until: Date)`, `edit(id: UUID, title: String?, dueAt: Date?)`, `setAlerts(id: UUID, offsets: [TimeInterval])`, `help`.

`CommandParser.parse(_ text: String, now: Date, timeZone: TimeZone) throws -> ReminderCommand`.

`NotificationIntent` fields: String `id`, UUID `reminderID`, String `title`, Date `fireAt`, Int64 `sourceRevision`. Stable identifier prefix `argus.reminder.`; never remove notifications outside this prefix. Result payload is not an instruction.

`ScheduleCalculator.notifications(for reminder: Reminder, now: Date, horizon: Date) throws -> [NotificationIntent]` generates sorted unique future alerts within a bounded horizon. Recurrence uses stored zone, Gregorian weekday rules, spring-forward next valid local time and fall-back first occurrence once. A snooze replaces the current occurrence's alerts without mutating the deadline. Completed records produce none. Cap per-reminder output at 64 with a visible error rather than silent truncation.

`QuietHours` validates start/end wall-clock components and timeZoneID; `nextAllowedDate(for date: Date) -> Date` defers times within the interval, including crossing midnight. Equal endpoints means disabled, not all-day. Use it in notification planning, not by changing source due dates. Emergency bypass is an explicit source/policy input, never OS Focus bypass.

## Task 1: Deterministic core (owned by core implementer)

Files: Package.swift, .gitignore, Sources/ArgusCore/{Reminder,ReminderCommand,CommandParser,ScheduleCalculator,NotificationIntent,QuietHours}.swift, Tests/ArgusCoreTests/*.swift.

- [ ] Establish a minimal Swift package target/test target without external dependencies.
- [ ] Write failing command tests before parser implementation. Representative executable test:

```swift
@Test func relativeReminderUsesInjectedClock() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let command = try CommandParser.parse("Remind me to leave in 20 minutes", now: now, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
    guard case let .create(title, dueAt, zone, recurrence) = command else { Issue.record("Expected create"); return }
    #expect(title == "leave")
    #expect(dueAt.timeIntervalSince(now) == 1200)
    #expect(zone == "America/Los_Angeles")
    #expect(recurrence == nil)
}
```

- [ ] Cover singular/plural minute/hour/day relative durations, zero/negative/overflow durations, unknown prose, empty text, strict UUID selection, ISO8601 edits, `alerts <uuid> 1d,1h`, `snooze <uuid> for 10 minutes`, `Every weekday at 8:30, show my morning briefing`, and unsupported grammar. The briefing wording creates a reminder only, not a future worker before that slice exists.
- [ ] Observe red with the selected toolchain's `swift test --disable-xctest --enable-swift-testing --filter ArgusCoreTests`; record failure evidence. Use `import Testing` and `import Foundation`. An environment/compiler crash is not behavioral red. No XCTest framework is available without full Xcode.
- [ ] Implement validating models and finite parser without eval, shell, or network.
- [ ] Write/fail/run scheduling tests: one-time offsets 86400/3600, duplicate normalization, stable IDs, past alert omission, snooze retaining dueAt, completion, weekday weekend skipping, DST gap/fold, horizon bound and no duplicate occurrence.
- [ ] Implement scheduling and quiet hours, then run `swift test` and `swift build`.
- [ ] Commit only owned files and provide public API notes plus exact test outcomes.

## Task 2: Durable store and notification reconciliation (owned by storage implementer after Task 1)

Files: Sources/CSQLite/{module.modulemap,shim.h}, Sources/ArgusStore/{SQLiteDatabase,ReminderStore,StoreError}.swift, Sources/ArgusPlatform/{NotificationClient,NotificationReconciler}.swift, Tests/ArgusStoreTests/*.swift, Tests/ArgusPlatformTests/*.swift. Coordinator owns Package.swift updates after Task 1.

Interfaces: `ReminderStore(databaseURL: URL) throws`, `list() throws -> [Reminder]`, `save(_ reminder: Reminder, expectedRevision: Int64?) throws`, `delete(id: UUID, expectedRevision: Int64) throws`, `desiredNotifications(now: Date, horizon: Date) throws -> [NotificationIntent]`. Store methods serialized by caller or internal lock; do not mark unsafe pointer state Sendable without isolation. Explicit schema version, bound SQL, transactions, foreign keys, WAL/FULL durability choice, bounded busy timeout. JSON payload is acceptable for validated reminder body plus indexed ID/revision; do not pretend SQLite is encrypted.

Notification intent recovery may be based on a durable desired-state generation in the same transaction as each reminder edit. Store that generation and expose `generation() throws -> Int64`. Reconciliation must not mark a stale snapshot current after intervening edits. Save DB truth before OS calls. No background worker queue yet.

`NotificationClient` async protocol: `authorizationStatus() async -> NotificationAuthorization`, `pending() async throws -> [NotificationIntent]`, `add(_ intent: NotificationIntent) async throws`, `remove(ids: [String]) async`. `NotificationAuthorization` values notDetermined/denied/authorized/provisional. Reconciler is an actor, single flight with dirty rerun, and only touches owned IDs. Authority changes invalidate stale snapshots. Errors leave desired state durable and visibly pending, never falsely delivered.

- [ ] Write real temporary-database tests first: save/list/reopen, edit revision increments, optimistic conflict, malformed zone data rejection, deletion/reopen, Unicode and SQL-looking titles preserved, failure without silent reset.
- [ ] Observe red, then implement minimal system-SQLite persistence.
- [ ] Write protocol-adapter tests for add/remove/edit idempotence, failure then restart/retry, unrelated pending notifications preserved, revoked permission, and mutation during delayed add. Fake OS boundary is permitted but test real reconciler behavior, not a mock expectation alone.
- [ ] Observe red, implement reconciler, run all tests.
- [ ] Deletion permission is enforced in the app service/UI before calling store; a worker can never access this API. Store delete requires exact revision, never a path.
- [ ] Commit scoped files, record test coverage and any unverified OS behavior.

## Task 3: Native app and macOS adapter (owned by app implementer after contracts compile)

Files: Sources/ArgusPlatform/UserNotificationClient.swift, Sources/ArgusApp/{ArgusApp,AppModel,TodayView,CommandBar,ReminderEditor,SettingsView,NoticeView}.swift, Config/Info.plist, scripts/build-dev-app.sh, Tests/ArgusPlatformTests/UserNotificationMappingTests.swift. Coordinator updates Package.swift.

- [ ] Test pure notification ID/content/date mapping and command-to-store transitions before implementing adapter/application service. No live authorization request from tests.
- [ ] Build a SwiftUI executable with original neutral sidebar, command bar, five-row Now/Approaching sections and expandable full list. Provide list/create/edit/snooze/delete flows; delete uses visible confirmation, reject does nothing, stale revision requires rereview.
- [ ] Reminder editor supports title, exact date/time/zone, weekday recurrence and alert offsets. Parse errors preserve typed text and show examples. Add shortcuts and accessibility labels.
- [ ] Show notification status saved/pending/scheduled/permission denied distinctly. Only request permission from explicit user Enable notifications control. A pending OS request is not user-observed delivery.
- [ ] Observe model-test red then implement UserNotifications adapter and stateful service. Reconcile at launch, edits, wake and permitted foreground opportunities; never rely solely on a SwiftUI timer.
- [ ] Add an explicit development bundling script that builds release executable into local build/ARGUS.app and ad-hoc signs for development only. Do not install into /Applications or register login launch. Never label ad-hoc output App Store-ready or sandbox-verified.
- [ ] Run `swift test`, `swift build`, development bundling, and codesign/plutil structural checks. Keep `build/` and `.build/` ignored.
- [ ] Demonstrate with synthetic data in an isolated temporary app-data directory, never populate the user's real schedule. Notification consent and actual banner testing remain a user-controlled native acceptance step if automation cannot perform them safely.

## Task 4: Independent review, failure tests and evidence

Files: docs/verification/2026-09-17-reminders-slice.md, README.md, tests needed for discovered defects.

- [ ] Independent reviewer examines spec compliance, real SQL paths, parser/calendar edge cases, optimistic conflicts, notification callback races and no-hidden-network policy.
- [ ] Reproduce each material finding with a failing test before fix. Rerun entire suite and app build.
- [ ] Verify restart using the actual persisted store and application service, not a copied implementation or mocks for SQLite.
- [ ] Inspect artifact Info.plist and signature. Record full Xcode/signed-sandbox/real notification limitations explicitly.
- [ ] Update README with truthful runnable commands and supported grammar. No prompt library, hands, voice, calendar, or App Store-ready claim until those slices exist.
- [ ] Commit scoped work, leave shared main and remote untouched, and checkpoint next slice and unresolved release gates.

## Pre-flight consistency scan

| Tasks | Shared contract/file | Resolution |
|---|---|---|
| 1 with itself | model/parser/scheduler | Parser creates proposals; no database or notification side effect. Recurrence is explicit and only weekdays initially. |
| 1 -> 2 | Reminder and NotificationIntent | Use Task 1 public types verbatim. Coordinator reconciles API changes before dispatch, not guessed duplicates. |
| 1 -> 3 | CommandParser | App interprets delete as proposal requiring visible confirmation. Unknown prose has no side effect. |
| 2 with itself | SQLite generation and OS adapter | Durable desired state is authoritative, callbacks cannot supply durable truth. OS calls are not SQLite-atomic. |
| 2 -> 3 | Store and NotificationClient | Storage has no SwiftUI dependency; user authorization requested only through explicit UI. |
| 2/3 | Package.swift | Coordinator owns manifest changes after Task 1 to avoid conflicting edits. |
| 3 with itself | dev bundle vs distribution | Ad-hoc local bundle is demonstrable development output, not a signed sandbox/release substitute. |
| all -> 4 | evidence | Swift tests establish domain/store/reconciler behavior. Real banners, Focus, wake/reboot and Mac App Store remain separate acceptance evidence. |
