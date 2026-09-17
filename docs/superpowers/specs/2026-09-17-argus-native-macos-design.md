# ARGUS native macOS design

Date: 2026-09-17
Status: Draft for user review. Native platform, Swift/SwiftUI/SQLite direction, and the three initial workflows are approved. This written security/release specification and implementation sequence are not yet approved. No application implementation has started.

## Product contract

ARGUS is a calm, local-first desktop assistant for reminders, reusable prompts, and bounded concurrent work. It is not a conversational model wrapper. Scheduling, notification reconciliation, search, preferences, permissions, task state, and orchestration must work with no language model and no network. Development agents and their providers are not runtime dependencies.

The user requested a full-stack app suitable for the Mac App Store. Here full-stack means native presentation, local domain services, durable storage, worker execution, and macOS adapters. It does not mean adding a cloud server, account system, analytics, or hosted model.

The initial hands are: prepare a prompt from explicit variables and selected context; search the local prompt library; prepare a fixed-rule briefing of deadlines and approval requests. None invents answers or executes arbitrary prose. Unsupported requests return a helpful supported-command example. Ambiguous commands require clarification.

## Scope and visual language

Use SwiftUI with selective AppKit integration only where a native capability requires it. Target macOS 14 or newer, subject to compiling the chosen API set. The development laptop is Apple Silicon. Support light/dark appearance, keyboard navigation, VoiceOver, reduced motion, and scalable text. Use system typography, comfortable whitespace, quiet separators, and one restrained accent. Take layout inspiration from ChatGPT and Notion without copying their branding or pretending to be their chat products.

A narrow collapsible sidebar contains Today, Prompts, Approvals, and Notices, with Settings below. Activity is available from item details and the data controls, not a default feed. Today shows a command bar, a small Now list, and an Approaching timeline. Now contains overdue items, deadlines within the next hour by default, active work, and approvals needing a decision. Approaching contains later deadlines through the next seven days. The urgency threshold is configurable. Each section initially shows at most five rows with a truthful remaining count. No charts, productivity scores, fake activity, or default debug panels. Hands is a small toolbar indicator with a detail view. Stop All remains accessible from every screen and the app menu. Do not show a decorative microphone before voice input exists.

The MVP accepts typed commands, creates/edits/lists/snoozes/deletes reminders, schedules local notifications, saves/tags/searches/edits/queues prompts, runs at most three safe hands, shows every hand's state and result, gates consequential operations, persists across restarts, and has a global stop control. Optional speech output follows the four core slices. Calendar integration follows voice and is isolated. Speech input is not required for the typed MVP.

No phone calling, email sending, purchasing, account modification, autonomous browsing, unrestricted shell, runtime plugins, or downloaded executable workflows.

## Components and dependency direction

- **Desktop interface:** renders domain snapshots and submits typed commands. It does not own scheduling truth.
- **Command interpreter:** parses a documented finite grammar into typed command proposals. It never uses eval, shell interpolation, or model output.
- **Scheduling engine:** pure time calculations with an injected clock and IANA time zones. Produces concrete occurrences and alert intents.
- **Notification adapter:** submits OS notification requests and reconciles desired versus submitted identifiers. Application requests do not prove the user saw an alert.
- **Prompt library:** immutable versions, metadata, search, variable validation, context snapshots, and execution references.
- **Local store:** SQLite transactions and migrations. Stores reminder and prompt records, job attempts, durable approvals, notification outbox, audit records, and settings.
- **Orchestrator:** validates approved workflows, schedules ready jobs, tracks leases/attempts, caps concurrency, and fences stale results.
- **Worker runtime:** executes only compiled allowlisted workflow implementations on bounded input snapshots. No direct database or credential access.
- **Permission registry:** maps typed operations to capabilities and approval requirements. It is enforced at the execution boundary, not just hidden in the UI.
- **Voice adapter:** optional outbound TTS only. Missing credentials and network failure do not block other features.
- **Calendar adapter:** initially a deliberately constrained import path, with preview and duplicate handling. Broader integration requires separate permissions.
- **Secrets adapter:** macOS Keychain. No keys in source, prompts, defaults, SQLite, logs, or exports.
- **Audit service:** understandable outcomes, approvals, cancellation, and verification evidence, with content redaction.

Core types must not depend on SwiftUI, UserNotifications, Keychain, or a voice SDK. Adapters implement narrow protocols. SQLite writes are serialized through the authoritative service, not directly performed by views or workers.

## Durable scheduling

Store UTC instants and IANA zone identifiers. Recurring schedules additionally retain wall-clock components, recurrence rule, and daylight-saving policy. An absolute one-time instant does not move when the system time zone changes. A recurring local schedule follows its explicitly chosen zone, not an implicit device setting.

Proposed DST policy: an invalid spring-forward wall time shifts to the next valid local time; an ambiguous fall-back time selects the first occurrence and fires once. Show the policy in settings and test it with fixed fixtures.

Support separate alert offsets on an occurrence. Each alert has a stable logical ID. Save changes and notification-outbox intents in one transaction. Reconciliation retries failed registration and cancels obsolete OS requests after edits. Snooze creates a replacement alert, not a duplicate original event. Store delivery observations separately from request acceptance.

On startup/wake reconcile pending requests and overdue occurrences. ARGUS emits at most one new catch-up notification or in-app summary per reconciliation rather than a flood. It cannot guarantee how macOS presents requests already delivered or queued independently while ARGUS was not running. Quiet hours defer ordinary alerts to the next allowed instant. An explicit per-item emergency choice may bypass ARGUS quiet hours but never claims to bypass macOS Focus or notification permissions. Notification denial is a visible degraded state.

Notices persist locally with source ID, occurrence/threshold ID, reason, observed time, and dismissal/snooze state. Snooze changes only the alert time, not the source deadline. Dismiss archives the notice without completing the source or approving an action. Reschedule edits the source with an explicit time-zone preview and cancels obsolete requests. Open navigates to the exact source; missing sources show a recoverable explanation. Provide all four actions in-app, with OS-banner actions only where supported.

Closing the window must not invalidate already scheduled OS requests. The smallest MVP keeps the main app/broker running with a menu-bar affordance after its window closes. Explicit Quit stops computation and preserves the queue for next launch. Already registered OS notifications remain independent of the running UI. Optional launch at login uses SMAppService only after consent. Continued computation after explicit Quit is a separate opt-in helper extension with a signed packaging/IPC prototype gate, not a hidden process. This distinction applies to ARGUS, separately from Jcode development-session persistence. No promise of execution while powered off, logged out, or asleep. Missed work is recovered after the next permitted start/wake. A pre-scheduled notification cannot recompute a fresh briefing at delivery time.

## Prompts and execution

A prompt contains ID, title, body, tags, optional project, created/modified dates, favorite flag, immutable version history, variable schema, optional context attachments, intended workflow, and archive state. Prompts has Inbox and Library tabs. Captures enter Inbox as drafts; explicitly saving a validated version moves it into the reusable Library. Editing creates a new draft/version, not a mutation of history. Archive/restore preserves versions. Queue entries reference a specific version and input snapshot, not the mutable latest prompt. Display draft/queued/running/completed/failed/archived projections without conflating one prompt with multiple execution attempts.

Use literal {{name}} placeholders with no nested expansion or expression engine. Reserve {{context}} for explicitly selected UTF-8 context joined by two LF characters in the user's displayed order. Missing required variables fail validation. Selected context without a context placeholder requires an explicit template edit, not silently appended content. Strings are data, never executable templates. Limits: ten context items, 1 MiB total encoded input, 2 MiB resolved output, fifty search results per page, and a thirty-second execution budget per attempt. Fail on excess size without partial truncation. A preview shows exactly what the workflow will receive. Editing an approved input invalidates approval instead of silently switching the payload.

A queued free-form prompt with no supported workflow becomes waiting, never a hidden model request. Scheduled time makes a job eligible; it does not grant missing permissions.

Search defaults to case-insensitive literal substring matching against title/body, with exact case-insensitive tag/project filters combined by AND. It has no regex, model ranking, or implicit query language. Freeze the search scope and normalization algorithm version. Order by normalized title then stable ID; return fifty records per page with total match count. Validate each hit against that snapshot and reject missing/duplicate/unmatched IDs. Never index encrypted bodies in plaintext.

Briefings include incomplete deadlines in [asOf, throughExclusive), overdue incomplete records when includeOverdue is enabled, and pending approvals as of the snapshot. Default horizon is 24 hours with includeOverdue enabled. Sort deadlines by due instant then ID, list approvals separately by creation time then ID, deduplicate records, and display snapshot time plus source links and matching rule. No inferred importance or generated conclusions. A changed source produces a stale-snapshot notice and an explicit Refresh action, not a rewritten historical receipt.

## Hands, results, and stop

At most three hands run concurrently; the default limit is three and the user may reduce it to one or two. A hand has a job ID, workflow ID/version, attempt ID, allowed capabilities, input digest, creation/eligibility/deadline times, state, result reference, and activity history. No hand may spawn another hand. Canonical stored/public states are queued, working, waiting, completed, failed, and cancelled. Verifying and stopping are working substages; paused/approval-required are waiting reasons; interrupted is a failed-attempt reason, not an incompatible seventh top-level state.

Lifecycle: queued -> working -> completed/failed/cancelled. Missing consent or a user pause enters waiting with a reason. Resume creates or claims an eligible attempt with the same immutable job input. Retry preserves the failed attempt and creates a new attempt. The UI distinguishes interrupted work from successfully completed work.

The orchestrator decomposes only predefined workflows into a known bounded dependency graph. It does not infer arbitrary tasks from prose. Ready work is ordered by explicit priority, eligibility time, and stable enqueue order. Limits include input/output size, execution deadline, and bounded retry counts.

Completion requires broker-side validation of job/attempt IDs, input digest, result schema, allowed output type, size, and workflow-specific postconditions. Validation failures are failed results, not success. Two outputs never silently overwrite each other. File exports require destination preview and explicit replacement consent.

Stop All atomically disables new dispatch and advances a cancellation generation, revokes active attempts and unconsumed execution approvals, signals worker cancellation, and rejects late results from old generations. An unresponsive isolated worker must have a tested termination path. Show stopping until termination is observed. XPC invalidation is not proof of process death: quarantine an unconfirmed slot and do not launch a replacement that could exceed the three-worker bound. Stop does not retract already-sent notifications or automatically disable reminders. Resume is explicit and requires fresh approval for invalidated consequential proposals.

After a crash, recover leases and classify unfinished attempts as failed with reason interrupted. The MVP requires explicit Retry for interrupted attempts and does not silently replay them. Future automatic retries, if introduced, may cover only side-effect-free approved deterministic jobs with a bounded policy. Never replay a consequential action merely because its completion record is missing.

## Security and platform isolation

Workers get only assignment-scoped snapshots, not a whole database connection, file-system root, integration credentials, or UI object graph. No worker network entitlement, application-group storage, shared Keychain access group, or broad file access. Separate processes alone are not a security boundary. Use three sandboxed embedded XPC service identities sharing source, one job per service. Three connections to a single service do not establish three processes. Their actual confinement and termination behavior are a release-blocking verification gate. No shell API or dynamic execution path is shipped; standard App Sandbox alone is not claimed to enforce a universal prohibition on every possible child-process execution by compromised native code.

The host/broker authenticates IPC peers and validates every message. Use the macOS Data Protection Keychain with kSecUseDataProtectionKeychain=true, non-synchronizable items, and the broker's explicit private access group for secrets and encryption keys. Worker identities receive no access to that group. Validate this with synthetic secrets in the signed build, not just entitlement source files. Capabilities are finite typed operations, not paths or arbitrary tool names. Webpage/file/email/tool-result text cannot create instructions, permissions, or new jobs.

Deleting user records requires explicit confirmation. Exporting or replacing external files requires destination-specific approval. Any voice transmission requires disclosure of the exact text or a narrowly selected nonsensitive response category. Approvals bind action, input digest, resource scope, and expiry, and are checked again immediately before execution. Denial is the default.

An approval is one-use, expires after 24 hours by default, and consumes into one logical durable effect record. Consumption is not evidence that an external effect succeeded. A shared serialized, non-reentrant effect gate checks the current cancellation/data epoch and initiates an OS effect without an intervening await. Late notification-add callbacks from stale epochs enqueue compensating removals; outbox reconciliation also covers lost callbacks. External file publication uses the same stop gate. An uncertain export result is waiting for reconciliation, never automatically retried into an overwrite.

The Approvals view displays the exact operation, source versions, destination/scope, resolved preview, consequences, and expiry, with separate Approve/Reject buttons. A local approval reminder is not an executable permission grant. No generic approve-everything control. Changed, expired, denied, consumed, or revoked proposals cannot execute. All decisions are keyboard accessible and remain distinguishable after restart.

Delete-all is a special ordered operation: consume its exact approval and commit the stop/erase intent together in one transaction, then durably store a minimal non-sensitive deletion manifest outside the to-be-erased database before removing data. Do not Stop All first and thereby invalidate the very approval needed to delete. Recovery resumes that approved erasure manifest, cancels owned notification IDs, and removes only app-owned data. Repeated restart must neither resurrect deleted data nor delete unrelated paths.

App Sandbox and FileVault are not equivalent to application-level encryption. Encrypt prompt bodies, context snapshots, resolved artifacts, and retained variable values using CryptoKit authenticated encryption with a broker-only Keychain-held key. Do not duplicate those fields into plaintext full-text indexes or audit messages. Search decrypts a bounded candidate set in trusted memory and sends only the approved search scope to a worker. Ordinary schedule metadata and prompt titles/tags may remain in the local database; disclose that limitation. Key unavailability fails closed for protected content while exposing an honest recovery state. Any helper-Keychain sharing would require a separate narrowly scoped trusted group and signed verification.

Inspection, correction, export, and deletion controls are required. Export excludes secrets. Deletion removes live records, derived indexes, attachments, and app-owned caches but does not promise forensic erasure from SSDs, OS backups, or copies previously exported by the user.

## Optional voice

Preferred ElevenLabs voice ID: `ysswSXp8U9dFpzPJqFje`. This is non-secret configuration, not an API key or evidence of voice access rights. Voice is disabled by default. Credentials are entered through a secure native settings flow and stored in Keychain. Do not ask for keys in chat.

A replaceable speech provider handles availability, speak, and cancel. Missing key, rejected voice, rate limit, and offline errors are explicit nonfatal outcomes. Remote speech can incur provider charges. No real provider request until the user knowingly enables it. Do not ship a developer-wide embedded key. App Store release must resolve lawful voice availability and any commercial-service policy requirements.

## Packaging and development constraints

The current machine has Swift 6.1.2 Command Line Tools and no Xcode application found in /Applications or ~/Applications. Core command-line tests may be feasible, but real app signing, entitlements, XPC packaging, archive validation, and UI tests require the full Xcode toolchain and appropriate account assets. Do not claim App Store readiness from a Swift package build.

An App Store release requires a stable bundle identity, Apple developer membership, signing/provisioning, supported sandbox entitlements, privacy disclosures/manifests where applicable, icons/screenshots, support/privacy URLs, archive validation, and review. Do not enroll, purchase, accept legal agreements, submit, or publish without the user's explicit action/confirmation. Store acceptance cannot be guaranteed.

## Implementation and approval gate

Build one verifiable vertical slice at a time: reminders/notifications; prompt library; queue/worker runtime; multi-hand orchestration; voice; calendar adapter; reliability/privacy/release testing. Each slice has observable acceptance criteria, tests before or alongside implementation, a demonstration, a relevant diff, failure/restart evidence, a safety review, and a scoped commit.

The three parallel design reviewers own docs/research/macos-release.md, docs/research/security-recovery.md, and docs/research/native-experience.md. These are supporting analyses, not alternate authoritative specs. This consolidated document controls proposed defaults when recommendations differ: one-hour Now threshold, concurrency three, the six canonical hand states, explicit retry after interruption, and encrypted protected content. Manual ambiguous one-time dates require clarification; the explicit DST policy applies to saved recurrences. Both friendly reminder grammar and structured advanced commands are supported. No reported UI or security acceptance test has yet been executed against an application.

## Background development

Jcode development work is distinct from ARGUS runtime background operation. Three headless design sessions have been started on the existing detached Jcode server. Durable initiative: `argus-native-macos-assistant`. Jcode documentation states an idle timeout after all clients disconnect; uninterrupted execution after closing every client is not yet established. Sleep/shutdown and loss of provider access stop active progress. Preserve artifacts and checkpoints so work can resume without pretending it continued.
