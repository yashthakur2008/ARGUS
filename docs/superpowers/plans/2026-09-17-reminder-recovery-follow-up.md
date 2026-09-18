# Reminder slice recovery follow-up

Status: implementation contract for the next bounded increment, after Tasks 1–3 compile and their initial contracts are reviewed. This closes gaps in the approved reminder slice, not a new product direction. Do not label the reminder slice complete before these journeys are implemented or explicitly blocked by real OS permissions.

## Why this increment exists

The initial store persists reminders and a desired-notification generation. It does not yet persist quiet-hours preferences or in-app notice dismissal. Replanning only future OS requests does not itself recover missed reminders. The Today screen can show overdue source records, but that is not the promised notification-center lifecycle.

## Smallest behavior

- Persist a notification policy containing optional validated quiet hours and an explicit user-controlled quiet-hours bypass. This does not bypass macOS Focus or permission denial.
- Persist in-app reminder notices independently of OS authorization. A notice records that its scheduled instant is due, not proof that an OS banner was delivered.
- Reconcile notice candidates at launch, wake, refresh, and reminder mutation with an injected clock.
- Scan recurring alerts over the most recent seven days. This bounds computation and coalesces long absences rather than replaying every historical occurrence. Include all due alerts for nonrecurring reminders, including older overdue reminders. Display one summary of reminders needing attention, not a burst of catch-up system notifications.
- Use the core scheduler's stable intent ID as the notice identity. Repeated capture and restart do not recreate a dismissed notice. Title-only edits do not invalidate dismissal of the same alert instant.
- Snooze changes neither the source deadline nor completion state. Persist snooze and the affected notice's dismissal in one transaction. Reschedule uses the same optimistic revision rules as editing and refreshes pending OS requests. Dismiss only changes notice state. Open resolves the current reminder by ID, or reports that the source is missing.
- Delete confirmation covers the selected reminder and its related notice history, never unrelated data.

## Implementation boundaries

Storage implementer owns schema migration, policy/notice value types, transactional APIs, and real-SQLite tests. App implementer owns native Notices and settings UI plus application-service tests. Coordinator integrates API contracts and runs independent verification. No new dependencies, system service, network, login registration, Keychain access, or OS permission request is needed for this increment.

Before implementation, the storage implementer must propose exact public signatures and schema migration steps for coordinator review. Do not make UI guess contracts or open raw SQLite connections to bypass the repository.

## Acceptance checks

1. Persist quiet hours, reopen the store, and observe deferred planned notification times without changing dueAt. Test crossing midnight, DST, explicit bypass, and denied OS permission.
2. Create two due alerts using the real store and injected clock. Capture once, reopen, capture twice again. The same notices remain, and the UI produces one catch-up summary rather than scheduling a burst of new OS alerts.
3. Dismiss one notice, reopen, recapture. It stays dismissed and the source is neither completed nor deleted.
4. Snooze a notice, reopen, and verify source dueAt remains identical, the old notice remains dismissed, and exactly the intended occurrence is postponed. Inject transaction failure and verify neither half commits.
5. Edit or reschedule with stale revision. Preserve the original notice/source until the conflict is resolved. Verify obsolete OS requests are replaced through the real reconciler with a fake OS boundary.
6. Open an existing source and a missing source. No fabricated destination or silent failure.
7. Upgrade a version-1 fixture without losing reminders, revisions, or generation. Reject corrupt/unsupported schema without reset. Test rollback of migration and concurrent writers.
8. Keep private reminder text out of generic OS notification previews and diagnostic logs. Document that reminder storage is local plaintext in this slice.

A real signed-app OS alert with the window closed, Focus behavior, sleep/wake, and macOS permission toggling remain separate native acceptance tests. Unit tests or pending-request equality do not prove delivery.

## Approved integration contract

The coordinator reviewed the storage proposal before implementation. Decisions:

- Seven elapsed days, not seven unspecified calendar days, bounds recurring catch-up.
- `PlannedNotification` contains the existing `NotificationIntent` plus sorted unique original `occurrenceDates`. `ScheduleCalculator.plannedNotifications(for:now:horizon:quietHours:bypassQuietHours:includingStart:)` shares one calculation with the existing notifications API. `includingStart` defaults to false. Historical capture opts into an inclusive start, including the earliest supported Date, without creating an invalid earlier input.
- A notice persists occurrence provenance. Never infer the source occurrence from its post-quiet-hours fire time or from the time its Snooze button is clicked. Coalesced notices require explicit occurrence selection. Snooze dismisses only the selected notice, and the UI explains that other notices remain independently dismissible.
- Store value types: validated `NotificationPolicy` with quiet hours, explicit bypass and revision; `ReminderNotice` with stable ID, source UUID, title snapshot, scheduledAt, sourceRevision, capturedAt, occurrenceDates and optional dismissedAt; `NoticeCaptureResult` with insertedCount, activeCount and recurringScanStart.
- Add store methods `notificationPolicy()`, `saveNotificationPolicy(_:expectedRevision:)`, `captureDueNotices(now:)`, `notices(includeDismissed:)`, `dismissNotice(id:now:)`, `reminder(id:)`, and `snoozeNotice(id:occurrenceAt:until:expectedRevision:now:)`. All throw on failure. Snooze validates the selected occurrence against both captured provenance and the current source, preserving dueAt and creation time.
- Schema 2 adds a singleton policy and related notice records with foreign-key deletion cascade. Migrate inside a transaction after validating version-1 identity/payload invariants. Existing reminder bytes, revisions and desired generation are preserved under the default policy. Reject corrupt or unsupported input rather than recreating it.
- Capture and dismissal do not change desired OS state, so they do not increment the notification generation. Policy edits and atomic source snooze do increment it once. Persisted notice truth is independent of macOS notification authorization.
- Add explicit `desiredSystemNotifications(now:)` and `reconcileSystemNotifications(now:)` methods. These register all finite future one-time alerts, but only seven days of recurring alerts. Existing bounded horizon APIs keep their original semantics. Both reconciliation entry points share one single-flight state machine.
- Add a month-away one-time alert and restart acceptance case. A one-time reminder must not depend on reopening the app seven days before its deadline merely to register with the OS. Recurrence beyond the rolling window still requires a later app run, and macOS presentation is never guaranteed.

These are implementation decisions, not claims that the recovery tests or native journeys have passed.
