# Commercial readiness checkpoint, 2026-09-18

**Decision: do not present this build as commercially ready.** This is a development prototype with verified local behavior, not a signed distribution release or a complete assistant MVP. Passing unit tests does not establish provider availability, hardware behavior, privacy compliance, or isolation.

## Evidence available

- Baseline `8a8a40e`: 299 Swift tests and development packaging/signature/runtime checks passed.
- `6b712ba`: recurring notice actions cannot overwrite a different occurrence's pending snooze. Tests use real disposable SQLite stores and verify reopening, generation stability, retained notices, quiet-hours deferral, legacy targets, and allowed same-target/expired behavior. Full suite: 303 tests passed.
- `feffea6`: snooze actions report persistence success explicitly. The editor dismisses only on success and retains input with an error otherwise. Full suite: 306 tests passed, including stale, expired, busy and successful paths. The view compiled and its action was reviewed. Native GUI interaction was not exercised for this change.
- `2d7f294`: README now distinguishes local reminder/recognition behavior from opt-in ElevenLabs HTTPS text-to-speech and no longer lists voice output as entirely unimplemented.
- Independent source reviews approved both snooze fixes. No production database, credentials, subscriptions, notification permissions, or remote repository history was changed during these fixes.

Raw red/green test output, task cards, and resource checks are retained in the local overnight run `overnight_1789716322778_9474728396623280354`. Tests use synthetic credentials and replaceable network/audio boundaries. No authorized live ElevenLabs speech test has been completed.

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
| Responsiveness and scale | SQLite work can occur on the main actor. Opt-in profiling exists but is not part of the default test count | Establish realistic data-size and contention budgets, measure UI responsiveness, then address demonstrated bottlenecks without an unreviewed storage rewrite. |
| Upgrade and recovery | Optimistic revisions and schema integrity tests exist. Development bundling is not an updater | Validate clean installation, upgrade, rollback, backup/restore and failure handling using disposable fixtures before touching user data. |
| Product completeness | Reminders, activation, deterministic speech and partial prompt-domain records exist | Complete and accept the prompt-library and bounded-worker workflows before marketing the full assistant MVP. Keep release notes scoped to what ships. |
| Licensing and operations | No top-level license file was found in this inventory | User chooses licensing/commercial terms and support/distribution arrangements. An agent must not select legal terms or publish on the user's behalf overnight. |

## Remaining bounded investigations

1. Very large finite alert offsets can be persisted and later make recovery fail. Existing tests deliberately allow dormant out-of-range candidates when replaced by snooze or completion. Any admission fix must preserve that contract and a repair route for existing records.
2. Ordinary reminder snooze selection uses raw `snoozedUntil`; an effective quiet-hours-deferred delivery can remain pending after that instant. The committed conflict safeguard applies to **notice snooze**, not every source-reminder action.
3. Changing quiet-hours policy can assign a new delivery identifier to a previously dismissed occurrence. Product semantics for acknowledgement across policy changes need explicit review before altering notice identity or history.
4. The packaging scout found that reusing an output bundle can retain stale files. A fresh staged-bundle fix and failure-preservation tests are being validated separately. No contamination of an installed app was observed.

## Operational limits of this checkpoint

Work is local and committed in small changes. Remote publication, credential/account changes, payments, live data migration and release submission are outside the overnight operating contract. Previous GitHub authorization polling was stopped. A future publish must preserve divergent remote history rather than force-pushing it.

This document records evidence and missing gates. It is not a claim that every gate can be completed without user decisions or that all testing can be replaced by synthetic fixtures.
