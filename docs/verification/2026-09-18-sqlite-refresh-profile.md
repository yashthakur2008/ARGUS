# SQLite refresh stall and retained-history profile

Date: 2026-09-18. Scope: production code read-only, disposable databases, no app launch, OS notification adapter, permission request, network, install, bundle, or push.

## Reproduce

The opt-in `SQLiteRefreshProfilingTests` use public `ReminderStore`, `ReminderRecoveryModel`, and `AppModel` APIs. They are disabled in normal test runs and have no elapsed-time pass/fail threshold.

```sh
SWIFT="${ARGUS_SWIFT:-swift}"
ARGUS_SQLITE_PROFILE=1 "$SWIFT" test -c release --disable-xctest --enable-swift-testing --filter SQLiteRefreshProfilingTests
# Repeat using the already-built test binary:
ARGUS_SQLITE_PROFILE=1 "$SWIFT" test -c release --skip-build --disable-xctest --enable-swift-testing --filter SQLiteRefreshProfilingTests
```

Each test creates a unique temporary SQLite database and removes its fixture afterward. The package has no external dependencies. Set `ARGUS_SWIFT` to select a specific installed toolchain. The measured executable was `/Users/yashthakur/.jcode/scratch/argus-swift-6.1.2/expanded/swift-6.1.2-RELEASE-osx-package.pkg/Payload/usr/bin/swift`.

## Production path and hypothesis

- `AppModel.swift:52-69`: `refresh()` is main-actor isolated. `store.list()` and `recovery.refresh()` execute synchronously before the first `await`. Declaring the method `async` does not move those calls off the main actor.
- `ReminderRecoveryModel.swift:15-20`: recovery calls `captureDueNotices`, loads **all** notices including dismissed notices, then loads policy.
- `ReminderRecovery.swift`, `captureDueNotices`: every capture takes the store's `NSLock` and a `BEGIN IMMEDIATE` write transaction, even on an empty database or an idempotent capture with no new notices.
- `SQLiteDatabase.swift`: the connection has `sqlite3_busy_timeout(..., 2_000)`. A competing writer can therefore keep that synchronous call waiting on the main actor. This is distinct from startup/migration races.
- Capture decodes all retained notices to build the deduplication set, decodes all reminders to calculate due plans, and decodes all active notices again to return `activeCount`. Recovery then decodes all history again. The reconciler separately reads reminders to plan system notifications after the main actor suspends.
- `SQLiteRecords.swift`, `readNotices`: history is decoded and validated row by row, with ordering by `scheduled_at DESC, id`. There is no pagination or history limit. Dismissal updates a timestamp, not deletion. The recurrence scan's seven-day bound limits discovery, not retained history. Deleting a source reminder cascades to its notices.

## Method

### Writer contention

Warm an empty model, measure an unlocked control, then use a separate SQLite connection to hold `BEGIN IMMEDIATE`. Verify the production WAL reader still returns an empty list. Queue a one-shot main-actor heartbeat immediately before `await model.refresh()`. Keep the writer locked until refresh returns, so timeout is deterministic without a sleep or a raced lock-release thread. Print monotonic refresh duration and heartbeat queue latency. Assert storage-error state, unchanged generation, and successful recovery after rollback, **not** a particular duration or scheduling order.

The heartbeat measures time until a ready main-actor task runs, not a periodic UI frame rate. Its unlocked queue latency approximates the synchronous refresh prefix but includes scheduling overhead. The held-lock case tests a completely empty database, so the stall does not require a large history.

### Bounded growth

Use 100 and 1,000 one-time reminders, each with one alert already due and no future notification to schedule. Fixture setup encodes public `Reminder` values into the production-created schema in **one** raw SQLite transaction and updates generation. Timed operations never use private/testable production APIs or copied production logic. Production `captureDueNotices` creates the notice payloads in one transaction.

Measure active history, then the same history fully dismissed. Exercise public dismissal once and bulk-update the remaining fixture timestamps outside timings, avoiding 1,000 expensive per-row FULL-sync writes. Production reads validate counts, payload identity, idempotent capture, and active counts. Startup, bulk seeding, and dismissal setup are excluded.

Each state gets a warm refresh followed by seven serial samples of list, no-op capture, all-history read, recovery refresh, full model refresh, and queued heartbeat. Store-only timings include small count-assertion overhead. Report min/median/max, not performance gates. Full refresh uses an in-memory denied-authorization client, not macOS notifications. It still exercises the real reconciliation planner.

Reminder count and history count grow together in this workload. The isolated `notices(includeDismissed: true)` measurement shows history-read cost, but the full-refresh change cannot be attributed solely to history. All results are warm-cache local measurements, not cold-start, disk-capacity, memory, SwiftUI render, real OS scheduling, or recurring-reminder measurements.

## Measurements

Environment: Apple M4, macOS 26.6.2 (25G83), arm64, Swift 6.1.2 (`swift-6.1.2-RELEASE`), optimized SwiftPM release tests. Two successive measurement invocations passed both tests. A separate invocation without `ARGUS_SQLITE_PROFILE` verified both tests are skipped. The final portable command above, with explicit Swift Testing flags, also passed both tests after the source changes were committed (held-writer refresh 2,091.515 ms, 1,000-active-row median refresh 34.786 ms and heartbeat 28.708 ms). Tables below retain the two original measurement runs. Earlier debug reproduction also passed, but its numbers are not compared as an improvement.

Measured production-source snapshot: **`244196bb5c452ff21ec28f131bb9a95ed41807e7`** on `feat/reminders-slice`. The build began at HEAD `e6125495dd601448dc4715ddf6a8b3fe83a7f419` with concurrent notification/migration working-tree changes. Those source bytes subsequently matched committed revision `244196b` exactly, verified with a clean `git diff HEAD -- Sources Package.swift` and the same source fingerprint. These results are not an untouched-e612549 baseline. Before and after the release build, and after the repeat run, every Swift source hash was identical. The sorted source manifest fingerprint was:

```sh
find Sources -name '*.swift' -print | sort | xargs shasum -a 256 | shasum -a 256
# f1f7dcabd918000bdf84cde61e8ac0fa8d9aa9b35b13ea6df9a3ce7820507e3f
```

Relevant measured file SHA-256 values:

| File | SHA-256 |
| --- | --- |
| `Sources/ArgusPresentation/AppModel.swift` | `1f6c8334f141f3dc63f8cc232819455d6af1a3bc13a058ef2596437684e78851` |
| `Sources/ArgusStore/SQLiteDatabase.swift` | `19402f2e8008a203cf598f1a7055819a4fdd1f6a087a63d60c1b6450c0ec16a8` |
| `Sources/ArgusStore/SQLiteSchema.swift` | `af9184dd70a8a516c40dbe97749e7872ccf070c89ac2aefd8747dd00e9561379` |
| `Sources/ArgusPlatform/NotificationReconciler.swift` | `769d2445274183d9f002e7b59d2c594bb7c5380bde67ba9fff1a0feab21ef815` |

### Empty-database writer lock (milliseconds)

| Run | Unlocked refresh | Unlocked heartbeat | Held-writer refresh | Held-writer heartbeat |
| --- | ---: | ---: | ---: | ---: |
| 1 | 0.105 | 0.064 | 2,095.271 | 2,095.306 |
| 2 | 0.099 | 0.048 | 2,091.934 | 2,091.953 |

The configured 2,000 ms is SQLite's busy-handler budget, not an exact wall-clock deadline. Both runs showed approximately **2.09 seconds** before the main actor could run the queued heartbeat. The held writer produced the expected storage error and the model recovered after rollback.

### Growth medians (milliseconds, seven samples per row)

| Run | Reminders / notices | Dismissed | List | No-op capture | All history | Recovery | Full refresh | Queued heartbeat |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 100 / 100 | no | 0.542 | 1.962 | 0.560 | 2.449 | 3.630 | 2.975 |
| 1 | 100 / 100 | yes | 0.519 | 1.337 | 0.564 | 1.883 | 3.102 | 2.417 |
| 1 | 1,000 / 1,000 | no | 5.326 | 19.557 | 5.533 | 24.088 | 36.236 | 29.913 |
| 1 | 1,000 / 1,000 | yes | 5.138 | 12.975 | 5.413 | 18.270 | 30.111 | 23.804 |
| 2 | 100 / 100 | no | 0.572 | 2.228 | 0.601 | 2.790 | 4.373 | 3.561 |
| 2 | 100 / 100 | yes | 0.539 | 1.392 | 0.574 | 1.932 | 3.193 | 2.496 |
| 2 | 1,000 / 1,000 | no | 5.467 | 19.922 | 5.556 | 24.720 | 36.429 | 29.989 |
| 2 | 1,000 / 1,000 | yes | 5.479 | 14.264 | 5.945 | 20.411 | 33.074 | 26.157 |

Across both runs, active-history full-refresh samples ranged from 3.586–5.349 ms at 100 rows and 35.494–38.945 ms at 1,000 rows. Active-history heartbeat samples ranged from 2.919–4.311 ms and 29.003–31.464 ms, respectively. Dismissed 1,000-row heartbeat samples still ranged from 22.506–28.012 ms. First production capture, measured once per fixture, took 4.926/2.831 ms at 100 rows and 26.095/23.263 ms at 1,000 rows (runs 1/2).

The larger fixture imposed a substantial synchronous prefix even when all notices were dismissed. This is a measured baseline, not a before/after optimization result or a claim about actual UI frame drops. The repeat command briefly waited for another SwiftPM process before its test timer began. The host was not otherwise isolated, so ranges and medians are descriptive, not service-level guarantees.

## Minimal follow-up recommendation

A held writer blocking even an empty refresh is material. The measured growth should guide an independently scoped responsiveness change, not a broad asynchronous migration in this investigation.

Plan a coherent background refresh snapshot plus guarded main-actor publication. Do **not** just wrap the current calls in detached tasks:

1. Define the snapshot boundary across reminders, due capture, history, and policy. Existing calls each acquire/release the store lock separately, so a collection of detached reads is not an atomic snapshot.
2. Guard both successful and failed snapshot publication against obsolete refreshes. The existing `refreshSequence` check occurs only after reconciliation, not before publishing initial reads or read failures.
3. Validate overlaps with save/delete/snooze, notice dismissal, and policy changes. Background capture holds the same lock that current main-actor mutation methods need, so moving only refresh can still block an overlapping mutation. Store generation increments for reminder/policy changes but not capture/dismissal, so generation alone is not a complete notice-snapshot freshness token.
4. Add controlled stale-success, stale-failure, and mutation-overlap tests, plus rerun this lock/heartbeat profile before claiming responsiveness improvements.
5. Separately consider an ID-only deduplication query and a count query, and bounded history presentation. Preserve corruption detection and dismissed-ID deduplication semantics. Arbitrarily pruning dismissed notices can cause recapture of past one-time alerts and needs an explicit retention contract.

No performance improvement is implemented or claimed here. A follow-up may be small, but its snapshot, invalidation, and mutation-ordering contract should be planned and tested before production edits.
