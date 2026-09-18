# Improvement batch: 2026-09-18

## Scope and baseline

This batch targets clean-build automation, malformed pending-notification recovery,
and measured SQLite reliability/responsiveness. It does not add a hosted runtime,
request notification permission, launch the app, or change signing credentials.

The coordinator's first `scripts/verify.sh` run at approximately 04:35 UTC failed:
134 tests ran, with `recoveryConcurrentMigrationAndWritersPreserveOptimism`
throwing SQLite code 5 (`database is locked`). Earlier passing checkpoints do
not invalidate this observed concurrent-startup failure. A focused reproduction
and fix were assigned before further optimization.

## Clean macOS CI

Commit `e612549` adds `.github/workflows/verify.yml`, reusing the existing local
verification script. It selects Xcode 16.4 through `DEVELOPER_DIR` on `macos-15`,
uses a SHA-pinned checkout with credential persistence disabled, grants only
`contents: read`, and requires no signing secrets. Concurrent superseded runs
are cancelled and each job is limited to 20 minutes.

Local YAML parsing, security invariant checks, shell syntax checks, and
`git diff --check` passed. The checkout SHA was checked against the upstream
v4.2.2 tag. The official runner-image inventory lists the selected Xcode path:
<https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md>.
Independent source review found no concrete CI issue.

**Hosted execution is blocked, not verified.** GitHub rejected the feature-branch
push because the existing OAuth credential lacks `workflow` scope. Credentials
were not modified or replaced. The workflow commit remains local until the user
authorizes an appropriately scoped credential. The selected Xcode version is
explicit, but the hosted image itself is not immutable.

## Verified local outcome, 04:41 UTC

The coordinator independently ran `scripts/verify.sh`: exit 0. Swift Testing
reported **150 tests passed**, with the two opt-in profiling tests explicitly
skipped in this normal run. Release compilation, development bundling, plist,
ad-hoc signature, and private runtime dependency/path checks passed. The profiler
was separately exercised twice in release mode, with both tests passing each time.

Afterward, the coordinator ran the two concurrent-startup regression functions
ten times using the already-built test binary. Each function has 20 argument
cases, for **400 successful concurrent-startup scenarios** across these repeated
runs. This is stress evidence, not proof against every process or filesystem race.

- `244196b` fixes the observed WAL transition failure. Preflight schema/payload
  checks use one read transaction. Only idempotent WAL setup retries `SQLITE_BUSY`,
  with a monotonic two-second budget and the SQLite busy handler disabled during
  that retry loop to avoid multiplying waits. The returned journal mode is
  verified. Ordinary writes are not automatically retried. Tests cover concurrent
  fresh opens/migration, optimistic single-winner updates, lock release, exhausted
  retry preserving file bytes/schema, and existing corruption/migration rollback.
- `77744a5` classifies pending notification snapshots without side effects.
  Unknown or ambiguous metadata versions fail closed before any cleanup.
  Reconciliation removes only explicitly classified malformed current/legacy
  owned IDs, checks generation/authorization, and verifies removal before normal
  scheduling. Foreign IDs remain untouched. Failed cleanup stays pending.
  Removal is OS ID-based, not atomic compare-and-delete against another writer.
- The [release profiling record](2026-09-18-sqlite-refresh-profile.md) reproduces
  a roughly 2.09-second queued-main-actor delay under an external writer lock.
  With 1,000 reminders/notices, active-history median full refresh was about
  36 ms and queued-main-actor latency about 30 ms on this host. These are baseline
  measurements, not performance improvements or actual SwiftUI frame-rate tests.

## Remaining external gates

Local tests and ad-hoc bundle checks do not establish live macOS notification
delivery, permission/Focus behavior, sleep/reboot reliability, signed sandbox or
Keychain boundaries, or App Store eligibility. Those gates remain separate.

## Reassessment boundaries

The next responsiveness change is not simply wrapping SQLite calls in detached
tasks. `AppModel.refresh()` currently publishes reads before its first suspension,
and guards its refresh sequence only after notification reconciliation. Moving
the reads introduces new success/error publication races. Reminder, notice and
policy reads use separate lock windows, and notice dismissal/capture do not advance
the notification generation. Generation checks alone therefore cannot establish
a coherent UI snapshot. Foreground mutations could also block on the same store
lock held by background work.

A follow-up should first define snapshot/publication semantics and tests for
overlapping refresh, dismissal, policy edits, and failed reads. No responsiveness
improvement is claimed in this batch. The opt-in profiler provides a reproducible
baseline rather than a timing-sensitive CI gate.

Likewise, adding a timeout around notification callbacks needs a lifecycle for
late side effects, not just abandoning an awaiting task. That broader change is
deferred rather than weakening the existing stale-add compensation rules.
