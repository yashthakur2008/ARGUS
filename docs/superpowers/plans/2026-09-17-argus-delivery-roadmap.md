# ARGUS phased delivery and verification plan

Date: 2026-09-17
Status: Delivery reference under the user's approved direction and subsequent explicit continuation instruction. This is a release roadmap, not evidence that any feature exists. The concrete reminders-slice plan records the first-slice implementation ruling and file layout.
Design: ../specs/2026-09-17-argus-native-macos-design.md

## Execution contract

Use the requested swarm for independent tasks with explicit file ownership, but deliver the slices below in order. Do not build unrelated subsystems in parallel before their contracts exist. Every slice uses test-first or test-alongside development, an independently reviewed diff, scoped commits, and user-observable evidence. Development providers never become application dependencies.

No live secrets, paid API requests, account changes, Apple enrollment, production publication, or App Store submission are authorized by this plan. The provided ElevenLabs voice ID is configuration only. No API key has been supplied. Reversible application implementation proceeds under the approved native direction and explicit continuation instruction, as recorded in the reminders-slice plan. Do not claim a separate written-spec review occurred.

## 0. Packaging and platform feasibility gate

Before claiming native notification, background, or worker-security behavior, install/configure full Xcode through the user's Apple account and verify the selected SDK. Do not accept legal agreements on their behalf. Core Swift package tests may run using Command Line Tools without implying a signed app is verified.

Files planned: Argus.xcodeproj/project.pbxproj, Config/Argus.entitlements, Config/Info.plist, Packages/ArgusCore/Package.swift, Tests/PlatformAcceptance/PackagingChecklist.md.

Deliverable before slice 1: a minimal signed development bundle with the intended sandbox and notification capability. Document the future worker target graph without implementing later slices early. No fabricated team IDs or credentials in source. Service embedding, broker-only Data Protection Keychain access, and worker termination are additional gates in slice 3. After-Quit helper registration/IPC is an optional extension, not a prerequisite for the main-app/broker MVP.

Acceptance:
- A development app launches without shell startup scripts or a hosted service.
- Signed entitlements match the declared allowlist, not only a source plist.
- Notification permission denial is handled without crashing.
- At slice 3's packaging gate, distinct worker slots are shown to use distinct confined processes.
- At slice 3's packaging gate, worker attempts to access the broker's private storage, Data Protection Keychain item, and network fail in a dedicated test build.
- Explicit consent governs any login registration. The MVP does not continue computing after explicit Quit. An optional after-Quit helper must pass its own consent/packaging gate before being offered.

Checkpoint: record signing identity category, SDK, OS, target names, observed outcomes, and untested items. If Xcode/signing prevents the real tests, mark this gate blocked and proceed only with clearly labelled core development after user approval. Do not replace this evidence with mocked tests.

## 1. Local reminders and notifications

Files planned:
- Packages/ArgusCore/Sources/ArgusCore/Reminders/{Reminder,ReminderCommand,ReminderService,ScheduleCalculator,QuietHoursPolicy}.swift
- Packages/ArgusCore/Sources/ArgusCore/Time/{Clock,RecurrenceRule}.swift
- Packages/ArgusCore/Sources/ArgusCore/Commands/CommandParser.swift
- Packages/ArgusCore/Tests/ArgusCoreTests/{CommandParserTests,ScheduleCalculatorTests,ReminderServiceTests}.swift
- Argus/Storage/{SQLiteConnection,MigrationRunner,ReminderRepository,NotificationOutbox}.swift
- Argus/Notifications/{UserNotificationAdapter,NotificationReconciler}.swift
- Argus/Features/Today/{TodayView,CommandBar,ReminderEditor,ApproachingView}.swift
- ArgusTests/{ReminderPersistenceTests,NotificationReconciliationTests}.swift
- ArgusUITests/ReminderJourneyTests.swift

Acceptance:
1. Typing `Remind me to leave in 20 minutes` proposes and saves one reminder due exactly 1,200 seconds after the injected clock time, with a stored IANA zone.
2. Create, list, edit, and snooze work through native controls and supported commands. Delete displays confirmation. Declining keeps both record and notification unchanged.
3. A deadline accepts one-day and one-hour alerts with stable distinct IDs. Editing it cancels stale notification requests and registers replacements.
4. A weekday 08:30 recurrence skips weekends and follows the documented DST policy.
5. The OS delivers a permitted local alert in a real signed app test with the window closed. Permission denial and Focus suppression are represented honestly.
6. Now shows overdue/urgent items without filling the screen with the whole database. Approaching remains chronological.

Failure/restart tests: crash after database commit but before OS registration; crash after registration but before acknowledgment; restart twice with no duplicate requests; denied permission; clock/zone change; spring-forward gap; fall-back overlap; snooze then edit; sleep past two alerts; quiet-hours crossing midnight. Catch-up is one summary, not a burst.

Demonstration: create a near-term reminder, close the window, observe the actual OS alert, reopen, snooze, edit, deny a deletion, confirm deletion, and restart to inspect persistence. In Notices, prove Snooze preserves the deadline, Dismiss does not complete it, Reschedule replaces obsolete requests, and Open reaches the correct source or an honest missing-source state. Repeat snooze/dismiss across restart and denied OS notification permission. Save a brief evidence record, not private notification text. Catch-up coalescing governs ARGUS-generated catch-up notices, not a guarantee about presentation of pre-existing macOS requests.

Safety review: parser rejects unsupported prose, reminders do not execute text, delete confirmation cannot be bypassed through a command alias, notifications do not disclose sensitive prompt bodies.

## 2. Prompt library

Files planned:
- Packages/ArgusCore/Sources/ArgusCore/Prompts/{Prompt,PromptVersion,PromptVariables,PromptSearch,PromptExecutionDraft}.swift
- Packages/ArgusCore/Tests/ArgusCoreTests/{PromptVersionTests,PromptVariablesTests,PromptSearchTests}.swift
- Argus/Storage/{PromptRepository,EncryptedContentStore}.swift
- Argus/Security/KeychainSecretStore.swift
- Argus/Features/Prompts/{PromptLibraryView,PromptEditor,VersionHistoryView,ResolvedPromptView}.swift
- ArgusTests/{PromptPersistenceTests,EncryptedContentTests}.swift
- ArgusUITests/PromptLibraryJourneyTests.swift

Acceptance: capture a draft into Inbox; validate/save it into Library; save title/body/tags/project/favorite; create immutable edit history; search by visible metadata and permitted body content; resolve declared variables; reject missing variables; show exact context and resolved preview; archive/restore without pretending to delete history. Inbox/Library state survives restart and has distinct empty states. Queue references a specific saved version and immutable snapshot. Before a worker runtime exists, queued items are visibly waiting, never falsely completed. Search fixtures prove case-insensitive literal title/body matches, exact tag/project filters, no regex execution, stable ordering, correct match counts, and duplicate-free fifty-row pagination.

Failure/restart tests: reopen the library after termination; simulate unavailable Keychain, changed/corrupt ciphertext and interrupted save; verify sensitive body fragments are absent from SQLite/WAL, logs, and derived indexes; edit a prompt after queueing and prove the queued snapshot did not change; submit injection-like placeholders and treat them as literal data.

Demonstration: create a tagged prompt with {{project}}, edit it twice, compare history, search, resolve variables, preview context, queue it, restart, and show the exact retained version.

Safety review: export excludes keys; imported context has no executable semantics; attachments require explicit scope; sensitive results are not silently spoken or indexed in plaintext.

## 3. Queue and worker runtime

Files planned:
- Packages/ArgusCore/Sources/ArgusCore/Jobs/{Job,JobAttempt,JobStateMachine,WorkflowRegistry,JobScheduler,ResultValidator}.swift
- Packages/ArgusCore/Sources/ArgusCore/Permissions/{Capability,Approval,ApprovalPolicy}.swift
- Packages/ArgusCore/Tests/ArgusCoreTests/{JobStateMachineTests,ApprovalPolicyTests,ResultValidatorTests}.swift
- Argus/Broker/{JobBroker,WorkerConnection,AttemptRecovery}.swift
- Argus/Storage/{JobRepository,ApprovalRepository,AuditRepository}.swift
- ArgusWorkerShared/{WorkerService,PreparePromptWorkflow,SearchPromptsWorkflow,BriefingWorkflow}.swift
- ArgusTests/{JobPersistenceTests,WorkerBoundaryTests}.swift

Acceptance: one safe workflow runs in an actual confined worker and returns a verified typed result. Unrecognized workflow IDs, capability requests, malformed payloads, excess input/output size, and stale input digests fail closed. Queued time controls eligibility but never supplies permission. Inputs changing after approval require new approval. The Approvals view shows exact action, source version, destination, preview, consequence, and expiry. Verify Approve, Reject, expiry, consumed-state, changed-input invalidation, keyboard navigation, and restart persistence using real UI journeys, not only policy unit tests.

Failure/restart tests: terminate the worker mid-job; terminate broker after claim; retry exactly one new attempt with preserved history; expire an approval; receive result after expiry/cancellation; duplicate a result; corrupt the result schema; unavailable worker service; deliberate worker timeout. No stale attempt may overwrite a new attempt.

Demonstration: prepare a resolved prompt, inspect inputs/result/activity, cancel a job, retry a failed attempt, and restart with a leased job to observe interrupted recovery.

Safety review: signed sandbox test evidence for worker separation; no arbitrary shell or tool invocation API; no recursive spawning; no database/Keychain/network permissions in workers; untrusted input never changes a workflow definition.

## 4. Three-hand orchestration

Files planned:
- Packages/ArgusCore/Sources/ArgusCore/Jobs/{WorkflowGraph,QueueOrdering,CancellationGeneration}.swift
- Packages/ArgusCore/Tests/ArgusCoreTests/{WorkflowGraphTests,QueueOrderingTests,GlobalStopTests}.swift
- Argus/Broker/{WorkerPool,GlobalStopController}.swift
- Argus/Features/Hands/{HandsIndicator,HandsView,HandDetailView,GlobalStopButton}.swift
- ArgusTests/{WorkerConcurrencyTests,StopRaceTests,OrchestratorRecoveryTests}.swift

Acceptance: queue five fixture jobs and observe no more than three actual active worker slots. The remaining jobs stay queued. A configured limit of one is enforced. Pause/resume has visible reasons and deterministic semantics. Each hand shows queued/working/waiting/completed/failed/cancelled, assignment, result, and activity. Declared dependencies gate ready jobs. Conflicting outputs remain separate until reviewed. Fixture-based independent result checks prove literal placeholder substitution without recursive expansion, exact search membership/order/counts, and briefing membership at asOf/throughExclusive boundaries, overdue inclusion, pending approval grouping, source provenance, deduplication, and deterministic ordering. A stale snapshot is visibly stale and never silently refreshed.

Failure/restart tests: stop during dequeue, stop during result commit, cancel an unresponsive worker, crash with three active jobs, resume a paused queue, exercise fixed-priority ordering under sustained arrivals, and submit cyclic/deep/oversized workflow graphs. Zero old-generation results may commit after Stop All. Do not equate XPC connection invalidation with proven process termination. Quarantine an unconfirmed slot rather than launch an additional process. Race Stop against file publication and stale notification callbacks through the shared effect gate; uncertain external effects wait for reconciliation, not automatic retry.

Demonstration: run the three approved workflows together, inspect their distinct verified results, queue additional jobs, press Stop All, show observed process termination and persisted cancelled/interrupted statuses, then explicitly resume future dispatch.

Safety review: concurrency measured at runtime, not only as an array size; cancellation cannot destroy reminders; no automatic worker spawning by workers; every output is validated before completed status.

## 5. Optional voice interface

Files planned:
- Packages/ArgusCore/Sources/ArgusCore/Voice/{SpeechProvider,SpeechRequest,VoiceConsent}.swift
- Argus/Voice/{DisabledSpeechProvider,ElevenLabsSpeechProvider,SpeechController}.swift
- Argus/Features/Settings/VoiceSettingsView.swift
- ArgusTests/{VoiceConsentTests,SpeechProviderContractTests}.swift

Acceptance: provider can be disabled/replaced without changing core services. Preferred voice is ysswSXp8U9dFpzPJqFje. Key entry uses native secure UI and Keychain. Before enabling remote speech, disclose transmission and possible provider costs. A local mock exercises request construction without network or billing. An explicitly authorized live test is a separate acceptance step and proves actual voice access, not merely a configured ID.

Failure/restart tests: offline, timeout, unauthorized/revoked key, voice unavailable, rate limiting, cancellation, and provider replacement. No key or private spoken text in logs. Notification/core workflows remain functional throughout failures.

Demonstration: enable with explicit disclosure, speak an approved nonsensitive response, cancel playback, disable voice, restart, and prove all local features still work with networking unavailable.

Safety review: TTS is the sole allowed external runtime integration in this slice; no speech-to-reasoning endpoint; no shared developer key. Speech input remains a separate opt-in extension, not a hidden MVP dependency.

## 6. Calendar adapter

Files planned:
- Packages/ArgusCore/Sources/ArgusCore/Calendar/{CalendarAdapter,CalendarImportPreview,CalendarConflict}.swift
- Argus/Calendar/ICSImportAdapter.swift
- Argus/Features/Calendar/CalendarImportView.swift
- Packages/ArgusCore/Tests/ArgusCoreTests/{CalendarImportTests,CalendarConflictTests}.swift

Acceptance: user-selected calendar file import provides a reviewable preview, retains time zones and event identities, detects overlap and duplicate UID/occurrence IDs, and applies only selected records after confirmation. Unsupported recurrence constructs are reported rather than silently approximated. Live EventKit account access is a separately reviewed adapter, not required for import.

Failure/restart tests: malformed/oversized input, unknown time zone, duplicate import, recurring-instance exception, all-day event boundaries, interrupted application of selections, and read permission loss. Import is transactional.

Demonstration: preview a fixture calendar with two overlapping entries, select one, import twice, show no duplicate, restart, and inspect provenance.

Safety review: no executable attachment handling, no remote URL fetching from imported data, no calendar write-back or account change.

## 7. Reliability, privacy, and App Store release

Files planned: ArgusTests/RecoveryAcceptanceTests.swift, ArgusUITests/AccessibilityJourneyTests.swift, docs/release/{acceptance-evidence,privacy-inventory,app-store-checklist}.md, Config/PrivacyInfo.xcprivacy if required by actual API/platform usage, release icon/catalog assets.

Acceptance: each requirement maps to a test or recorded real-device observation. Validate clean upgrade migrations and reopen behavior, worker confinement, data inspection/correction/export/deletion, no-secret exports, key loss behavior, offline core operation, global stop under load, and accessibility. Measure resource use during idle and during three hands without inventing a performance claim.

Use actual signed app targets for notification/background/worker tests. Use full Xcode UI testing and a validated archive for release. Verify App Store-specific sandbox, helper/login consent, privacy statements, minimum OS, icon/screenshots, legal voice availability, distribution identity, and metadata. Test Apple Silicon first, and only advertise Intel if that build and runtime have actually been validated.

Failure/restart tests: process kill at transaction boundaries, OS restart, sleep/wake, disk-full write failure, locked/unavailable Keychain, invalid migration, corrupted stored input, notification permission removal, disabled login item, cancelled approval, malformed IPC, and an interrupted release build. For delete-all, prove approval consumption and stop/erase intent commit together, the minimal erasure manifest survives database deletion, interrupted deletion resumes safely, stale OS callbacks cannot recreate app-owned notifications, and no unrelated paths are touched.

Demonstration: install the signed candidate, complete the main journeys with external networking disabled, enable only an explicitly approved voice test if desired, restart the Mac in a user-approved test window, and review the evidence matrix. Do not claim unattended restart validation without actually performing it.

Safety review: independently audit entitlements, provider endpoints, logs, exported artifacts, worker tooling, and permission checks. A successful build is not App Store acceptance. Apple enrollment, paid purchases, submission, and publication remain human-controlled gates.

## Verification record format

For each slice commit, record: requirement ID; acceptance scenario; command or UI steps; OS/SDK/build identity; expected result; actual observed result; relevant test/fixture path; artifact location; remaining limitations. Keep synthetic, real-adapter, signed-app, and manual evidence distinguishable. Never record sensitive customer content as test evidence.

## Dependencies and resumability

Core dependency order: 0 -> 1 -> 2 -> 3 -> 4 -> core-relevant checks in 7. The full requested delivery sequence then includes optional voice (5), calendar (6), and a repeat of 7 covering whichever adapters are included. Missing voice credentials or a deferred calendar adapter do not block an offline core release candidate. Do not advertise an omitted optional feature as shipped. Pure-core tests can proceed without the full packaging gate only after approval, and their limited evidentiary scope must be explicit. No claim for a later slice until its prerequisites pass.

The durable Jcode initiative `argus-native-macos-assistant` tracks next steps. Source and design checkpoints live in this repository. Background development depends on the Jcode server staying alive and the laptop being awake. The documented all-clients-closed idle timeout remains a limitation, not a verified unattended guarantee.
