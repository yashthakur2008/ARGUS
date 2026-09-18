# Commercial readiness checkpoint, 2026-09-18

**Decision: do not present this build as commercially ready.** This is a development prototype with verified local behavior, not a signed distribution release or a complete assistant MVP. Passing unit tests does not establish provider availability, hardware behavior, privacy compliance, or isolation.

## Evidence available

- Baseline `8a8a40e`: 299 Swift tests and development packaging/signature/runtime checks passed.
- `6b712ba`: recurring notice actions cannot overwrite a different occurrence's pending snooze. Tests use real disposable SQLite stores and verify reopening, generation stability, retained notices, quiet-hours deferral, legacy targets, and allowed same-target/expired behavior. Full suite: 303 tests passed.
- `feffea6`: snooze actions report persistence success explicitly. The editor dismisses only on success and retains input with an error otherwise. Full suite: 306 tests passed, including stale, expired, busy and successful paths. The view compiled and its action was reviewed. Native GUI interaction was not exercised for this change.
- `2d7f294`: README now distinguishes local reminder/recognition behavior from opt-in ElevenLabs HTTPS text-to-speech and no longer lists voice output as entirely unimplemented.
- `41d0556`: AppModel preflights active raw alert arithmetic before saving user commands, drafts and ordinary snoozes. Eighteen before-fix assertions reproduced the failure. Full suite: 312 tests passed afterward. Existing bad records can still be opened and repaired, and dormant snoozed/completed fields retain their prior storage contract.
- `b2e623f` and `e79ad38`: packaging builds a fresh staged bundle, validates before replacement, preserves rollback data on failure, and refuses competing packagers. The standard verification entrypoint passed 14 synthetic packaging regressions, 312 Swift tests, and a real development release build with signature/runtime checks. SIGKILL/power-loss recovery remains manual, not an atomic exchange guarantee.
- `b218cfd`: ordinary UI/command snoozes preserve a quiet-hours-deferred occurrence target. The save fences both reminder and policy revisions atomically. Existing unfenced store compatibility is unchanged.
- `72d74b2`: voice lifecycle monitoring and startup gating attach before any Scene exposes capture controls. Settings-first, failed storage startup, duplicate attachment and termination paths have fake-boundary regressions. Integrated verification passed **324 Swift tests, 14 packaging regressions, and real development release bundle/signature/runtime checks**. No native capture or launch-order acceptance was performed.
- Independent source reviews approved the earlier snooze fixes and admission guard. No production database, credentials, subscriptions, notification permissions, or remote repository history was changed during these fixes.

Raw red/green test output, task cards, and resource checks are retained in the local overnight run `overnight_1789716322778_9474728396623280354`. Tests use synthetic credentials and replaceable network/audio boundaries. No authorized live ElevenLabs speech test has been completed.

See the [source privacy API inventory](2026-09-18-privacy-api-inventory.md) for concrete preferences, elapsed-time, microphone, recognition, networking and packaging review points. No privacy reason codes or compliance outcome have been asserted.

## Release gates

| Gate | Current evidence | Required before making the corresponding release claim |
| --- | --- | --- |
| Distribution identity | `org.argus.local.development`, ad-hoc signature, no TeamIdentifier in the inspected development bundle | Choose distribution channel, configure the user's authorized signing identity, build a clean archive, and validate the selected distribution path. Do not invent signing or notarization success. |
| Process and secret isolation | Login-Keychain current-app ACL, not broker-private storage. Signed worker/isolation design is not implemented or runtime-proven | Implement the approved security boundary, then use signed synthetic-secret negative-access tests. Review entitlements and credential denial/rebuild behavior. No real secret is needed for the isolation tests. |
| Data confidentiality | Reminder SQLite is plaintext. A protected local directory is not encryption | Resolve the approved encryption/storage design and a reviewed migration/rollback plan. Do not perform an overnight migration of user data. |
| Privacy disclosures | UI/README disclose optional transmission, provider usage, and development Keychain limitations. No `PrivacyInfo.xcprivacy` or entitlement file was found in `Config` or `Sources` during this inventory | Audit actual API usage and distribution requirements, provide accurate privacy materials, and declare only verified purposes. This inventory is not a legal or App Store compliance verdict. |
| Provider acceptance | Fixed ElevenLabs voice and bounded request behavior covered by fake-boundary tests. No key configured by this work | User-authorized credential setup, entitlement/voice check, bounded live synthesis, audible quality and cancellation verification. Do not enable consent automatically or incur unapproved charges. |
| Hardware and lifecycle | Synthetic capture/speech/lifecycle tests, plus older native visual checks | Real clap/name activation, permission denial/revocation, screen lock/sleep/wake, multiple displays, long-running sessions and launch-at-login acceptance on supported Macs. |
| Notifications | Saved/pending/scheduled states are distinct. Reconciliation and SQLite recovery tested | Verify actual banners, Focus/permission behavior, reboot/sleep and recurring rolling-window limitations. Do not promise hard-real-time or critical-alert reliability. |
| UI and accessibility | Native SwiftUI controls and accessibility labels exist. Snooze failure branch compiles | Exercise VoiceOver, keyboard navigation, reduced motion, scaling, empty/error states and interrupted edits in the native app. Compilation alone is not accessibility acceptance. |
| Responsiveness and scale | Release diagnostics measured a **2204.5 ms** queued main-actor heartbeat while a second fixture connection held the SQLite writer lock. With 1000 active history rows, refresh median was **35.246 ms**, heartbeat median **28.815 ms** over seven samples. Both diagnostic tests passed, but the blocking defect remains | Establish realistic contention budgets and isolate storage work from UI execution with stale-result and repair-path tests. User mutations must also be examined, not just refresh. Do not mask the problem by weakening storage durability or pretending a diagnostic pass meets a responsiveness budget. |
| Upgrade and recovery | Optimistic revisions and schema integrity tests exist. Development bundling is not an updater | Validate clean installation, upgrade, rollback, backup/restore and failure handling using disposable fixtures before touching user data. |
| Product completeness | Reminders, activation, deterministic speech and partial prompt-domain records exist | Complete and accept the prompt-library and bounded-worker workflows before marketing the full assistant MVP. Keep release notes scoped to what ships. |
| Licensing and operations | No top-level license file was found in this inventory | User chooses licensing/commercial terms and support/distribution arrangements. An agent must not select legal terms or publish on the user's behalf overnight. |

## Remaining bounded investigations

1. Raw active-offset admission is now checked at the AppModel boundary. This does not validate every quiet-hours policy or future-delivery boundary. Core decoding and the direct store API deliberately retain compatibility, including dormant out-of-range fields and explicit repair of existing records.
2. Both notice and ordinary reminder snooze routes now respect effective quiet-hours-deferred delivery. Ordinary snooze additionally rejects saves if the policy snapshot changed before its transaction. This does not establish every future calendar or policy-boundary case.
3. Changing quiet-hours policy can assign a new delivery identifier to a previously dismissed occurrence. Product semantics for acknowledgement across policy changes need explicit review before altering notice identity or history.
4. Fresh staged packaging and failure-preservation checks now pass. Inspect and recover a retained `.ARGUS-backup.*` and `.ARGUS-packaging.lock` after an uncatchable interruption before starting another package. No contamination of an installed app was observed.

## Operational limits of this checkpoint

Work is local and committed in small changes. Remote publication, credential/account changes, payments, live data migration and release submission are outside the overnight operating contract. Previous GitHub authorization polling was stopped. A future publish must preserve divergent remote history rather than force-pushing it.

This document records evidence and missing gates. It is not a claim that every gate can be completed without user decisions or that all testing can be replaced by synthetic fixtures.
