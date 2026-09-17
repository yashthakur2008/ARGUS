# macOS release and isolation research

Research date: 2026-09-17. Scope: design and research only. No application, helper, entitlements, signing assets, account changes, software installation, or publication was created by this research.

## Decision summary

A Swift/SwiftUI app with a local SQLite store, system-scheduled reminders, and three fixed, compiled workflows is a plausible Mac App Store product. It is **not currently App Store-ready**, and neither a design document nor a successful archive guarantees review acceptance.

Recommended minimum architecture:

1. A sandboxed native app owns the UI, durable database, reminder reconciliation, and trusted broker. Closing its windows need not quit it. Optional launch at login uses `SMAppService.mainApp`, with explicit consent.
2. Three separately identified, embedded, sandboxed XPC services share one worker source module. Each accepts at most one bounded job at a time. This is a practical way to provision three worker slots without assuming three connections to one service create three processes.
3. Workers implement only template preparation, search/ranking over supplied library snapshots, and a fixed-rule briefing. They cannot choose executable paths, run commands, execute templates as code, access the database, request credentials, or initiate network operations through the application protocol.
4. Use `UNUserNotificationCenter` to register reminder notifications ahead of time. Notifications do not require the app to remain running. A notification is not a mechanism for executing a workflow on deadline.
5. Add a consented embedded login helper only if computation after **explicitly quitting the main app** is a firm requirement. This increases packaging, IPC, storage-ownership, and lifecycle complexity and requires a signed prototype before release commitment.

This is a local frontend and local backend, not a localhost HTTP service or a hosted backend. No server, account, cloud inference, scripting runtime, downloaded executable plugin, or worker network entitlement is needed for these workflows.

## Observed environment and limits of this investigation

- Working tree initially contained only an eight-byte `README.md`; no app project existed.
- Supplied environment: macOS 26.6.2, arm64, Swift CLT 6.1.2, selected developer directory `/Library/Developer/CommandLineTools`, and `xcodebuild` reports that full Xcode is not the selected developer directory. These version details were provided by the coordinating task, not independently re-measured here.
- Independently ran `find /Applications -maxdepth 2 -iname '*Xcode*.app' -print`. It returned no matches. Thus full Xcode was not found in the checked application locations, not merely unselected. The coordinator also reported checking `~/Applications` with no Xcode found. This is not a search of every disk or custom installation path.
- CLT may support some Swift compilation. That does not establish the Xcode project, signed nested-bundle archive, export, entitlement, and App Store validation workflow required here.
- No credentials, certificates, Keychain contents, Developer Program membership, or App Store Connect account were inspected. Account readiness is unknown, not proven absent.
- Current Apple pages and Apple documentation archives were read. Search encountered an anti-bot response, so known official URLs were fetched directly. One JavaScript fetch attempt timed out; direct fetch/curl supplied the relevant review-rule excerpts. No runtime or signed-package claims were tested.

## App Sandbox and process isolation

Apple requires App Sandbox for Mac App Store distribution [A1]. Its XPC guide explicitly distinguishes privilege separation using each XPC service's own sandbox from `NSTask`/`posix_spawn` children that inherit the parent's sandbox [A2]. Apple's current embedded-tool guide likewise explains sandbox inheritance and recommends XPC in many cases [A3]. Therefore:

| Component | Proposed capabilities | Deliberately excluded |
| --- | --- | --- |
| Native app / trusted broker | App Sandbox, its private application data, notifications after authorization; user-selected import/export only if implemented | Network client/server, broad filesystem grants, automation/accessibility, root privileges, dynamic code |
| Worker A/B/C | App Sandbox, distinct bundle/code identities, narrowly typed XPC interface, private scratch space only | `com.apple.security.inherit`, app groups, shared Keychain groups, network client/server, user-selected files, security-scoped bookmarks, database handles, secret access |
| Optional login broker | App Sandbox, consented ServiceManagement registration, durable scheduling and state | Root/daemon installation, automatic registration without consent, worker-style untrusted execution |

Do not pass file descriptors, security-scoped bookmarks, arbitrary URLs, listener endpoints, database paths, or credential-bearing objects to workers. These can delegate capabilities even when a worker's entitlement list appears narrow. Do not add temporary sandbox exceptions to make a failing architecture appear functional.

### Three workers, not merely three queues

Use three XPC service target identities, for example `ARGUS.Worker1`, `ARGUS.Worker2`, and `ARGUS.Worker3`, all built from shared source. Bundle each once under the actual host's `Contents/XPCServices`. Use one broker and a persistent queue with at most three active leases, one per service. Do not run separate independent worker pools in the UI app and a helper.

A service identity defines a service boundary. Apple describes a connection as a virtual endpoint, with the service launched on demand [A2]. It does **not** follow that opening three `NSXPCConnection`s to the same service yields three isolated processes. Conversely, three bundle IDs are a design proposal to validate, not evidence of the final process topology. Confirm distinct PIDs and signed identities under load, reconnection, and helper hosting.

Each service must reject a second job while busy, enforce payload/result size limits, and decode only allowlisted classes or a narrow versioned value schema. Include job ID, attempt/lease ID, workflow kind, input revision, and explicit resource limits. Treat malformed outputs as untrusted. The broker validates output and commits it transactionally. No worker writes durable application state directly.

XPC services can be killed when idle or interrupted during work, and Apple recommends minimal state [A2]. Retrying an interrupted job requires idempotency and stale-result rejection, not an assumption that the original attempt never finished. Invalidating a connection is **not** proof that an executing process stopped. Do not recycle a timed-out slot into a fourth live computation. Signed stress tests must establish cooperative cancellation and bounded work behavior. If the requirement means no more than three OS processes even during crash/restart transitions, that stricter lifecycle invariant remains unverified.

### What “no shell / no network” can honestly mean

- **No shell functionality:** the worker's shipped implementation has no `Process`, `NSTask`, `system`, `posix_spawn`, AppleScript, dynamic library/plugin loading, scripting engine, or command-evaluation pathway. Templates are escaped data, not programs. Source and dependency review enforce this contract.
- **No network capability:** omit both network entitlements in all worker signatures and do not delegate pre-opened sockets. Apple documents that network entitlements restrict connection initiation, and TCP data can flow both ways over an established connection [A4]. Test direct outbound/inbound attempts and accidental network frameworks in the signed app.
- **Not an absolute security theorem:** standard App Sandbox is not an arbitrary custom deny-all execution policy. Absence of a network entitlement is not proof against every possible system-service or delegated-IPC channel. An XPC sandbox does not by itself establish that a compromised worker can never execute an inherited-sandbox child. If an OS-enforced universal `exec` prohibition is mandatory, the current public-API design has an unresolved requirement. Do not claim this guarantee or introduce deprecated custom sandbox profiles, `sandbox-exec`, or private APIs to obtain it.
- These fixed workflows substantially reduce attack surface because the user supplies data, not executable instructions. The intended threat model is buggy or compromised processing of that bounded data, not arbitrary third-party code execution or protection against an administrator controlling the Mac.

## Secrets: concrete Keychain boundary

The simplest launch version has **no API credentials at all**: all approved workflows are deterministic and local. Keep a secret boundary in the design for future features without making a credential manager part of this release.

If broker secrets are later needed:

1. Store them in the **Data Protection Keychain** using `kSecUseDataProtectionKeychain = true` and non-synchronizable items. Apple's entitlement-based access-group sharing guidance applies on macOS when using this key or synchronizable items [A5]. Do not silently assume legacy file-based macOS Keychain ACL behavior is identical.
2. Explicitly select the broker's private access group when creating/querying items. Workers have different application identifiers and no access to that group. Do not add workers to the broker's app group: Apple notes that app groups can also confer Keychain sharing [A5]. Signing everything with the same team does not by itself require sharing each app's private group.
3. If both UI and login broker genuinely need a secret, provision a narrowly scoped shared Keychain group only for those trusted targets. Prefer broker-only ownership instead. Inspect the **exported distribution** entitlements, not just source `.entitlements` files.
4. No secrets in SQLite, worker messages, environment variables, launch arguments, notifications, logs, exception text, temp files, crash attachments, or broker callbacks. A worker may return a prepared artifact, but may not ask the broker to resolve an arbitrary credential name or perform arbitrary I/O on its behalf.
5. Negative signed tests must prove each worker cannot retrieve a known **synthetic test secret**, open the broker database/container, or cause the broker to return credentials. Use generated test data only, never real user credentials.

“No worker receives application credentials” is supportable after those checks. “Workers cannot access any secret anywhere on macOS” is too broad and is not established by this research. The broker can still accidentally include sensitive user text in a job snapshot, so snapshot minimization and redaction remain necessary.

## Background work, notifications, and sleep

Apple's current notification documentation states that the system handles a scheduled notification when the app is not running [A6]. Ask permission in context, ideally when saving the first reminder, and check current settings because users can change them [A7]. Do not require notifications to use the prompt library.

| State | Honest behavior contract |
| --- | --- |
| Main window closed, process still running | Broker may keep processing bounded jobs. Show a menu-bar/status affordance and make the continued-running behavior understandable. |
| Main app explicitly quit, no helper enabled | No new app computation. Already registered system notifications may still be delivered. Persisted work resumes next launch. |
| Consented login helper enabled, UI app quit | Helper may continue bounded work while macOS permits it. Show the consent and status clearly. This is not a guarantee of continuous runtime. |
| Notifications denied, alerts disabled, or Focus active | Preserve reminder state and show an in-app due/overdue list. Do not promise a banner or audible alarm. |
| Mac asleep or powered off | No promise that application code runs or that an alert occurs at its wall-clock deadline. Reconcile missed work when execution resumes. Delivery presentation/catch-up across sleep, restart, and user settings needs physical-device testing. |
| User logged out, helper disabled, or system terminates process | No guaranteed workflow execution. Recover persisted work at next allowed run. A user-session login item is not a pre-login system service. |

“Deterministic reminder” should mean deterministic date/recurrence calculation, stored timezone semantics, idempotent registration identifiers, and predictable recovery, **not hard-real-time notification delivery**. Specify DST gaps/folds, calendar recurrence versus elapsed durations, timezone changes, clock changes, and missed-occurrence policy.

A pending notification contains content prepared beforehand. It cannot recompute a live briefing at its delivery time. Either prepare the briefing when execution is available or send a neutral reminder to open ARGUS. Do not describe a stale precomputed briefing as newly calculated.

`NSBackgroundActivityScheduler` is suitable for deferrable maintenance. Apple expressly allows timing flexibility for energy, thermal, and CPU conditions [A8]. It is not an exact reminder timer, a process-resurrection guarantee, or a reason to prevent sleep. No continuous sleep-prevention assertion is proposed.

### Login helper and App Store feasibility

`SMAppService` is the modern API for embedded login items, agents, and daemons on macOS 13+ [A9]. Registration is subject to user approval. A registered login-item bundle starts immediately and on subsequent logins; Apple describes relaunch after crash/nonzero exit [A10]. Handle disabled/approval-required/error states visibly. No privileged daemon is needed.

App Review 2.4.5 requires appropriate sandboxing, self-contained Xcode packaging, no root escalation, and App Store updates. Crucially, 2.4.5(iii) disallows startup/login auto-launch **or processes continuing after Quit without consent** [A11]. Thus an opt-in login helper is not categorically ruled out, but Apple does not guarantee acceptance of this particular app.

Prefer two clear choices: “Launch ARGUS at login” and, only if supported, “Continue background work after quitting ARGUS.” A user must be able to turn the latter off, see current state, and choose “Quit ARGUS and stop background work.” Closing a window, quitting the UI, unregistering login launch, stopping current execution, and canceling reminder notifications are separate operations. Explain their effects rather than conflating them. System Settings can override the app's requested state.

**Simplest v1:** one main app/broker, three embedded services, system notifications, and optional `SMAppService.mainApp` registration. This meets background work after closing windows but not after actually quitting the process.

**If after-Quit computation is non-negotiable:** one bundled login broker owns the database and the single worker pool; the main app is an IPC client. The helper is a target under `Contents/Library/LoginItems`. Its own embedded XPC services must be placed under the actual host helper's bundle and validated in an exported signed app. Avoid duplicating the worker bundles under both hosts and accidentally allowing six active workers. Keep SQLite private to the broker where feasible. If an app group is required for trusted UI/helper discovery, grant it only to those two targets, never workers.

The trusted UI-to-login-broker IPC/bootstrap mechanism, peer code-identity validation, helper-hosted XPC discovery, foreground use when background consent is off, and notification bundle identity/authorization are **prototype gates**, not solved by simply putting helper source files in a Swift package. Apple states embedded XPC services are private to their containing application [A2], so do not assume the UI can directly connect to services embedded in a different helper host. Choose a supported app-group/Mach-service or listener-endpoint arrangement only after verifying the precise sandbox and signing requirements. Do not grant a broad Mach lookup exception as a shortcut.

## SQLite durability and reminder consistency

The following are engineering recommendations, not claims Apple has certified ARGUS's database behavior:

- One trusted broker is the only writer. Workers get immutable bounded values, not SQLite handles or filesystem access. Keep parameterized library queries in the broker and send only selected candidate records for ranking/filtering.
- Store prompts, reminders, workflow requests, attempt leases, artifacts, and notification-outbox intentions transactionally. A job becomes accepted only after its enqueue transaction commits. A completed artifact and terminal job state commit together.
- Use SQLite's system library with explicit foreign keys, busy handling, schema migrations, and an intentional journal/durability configuration. WAL with `synchronous=FULL` is a reasonable candidate for this small local workload, but benchmark and power-loss-test before claiming durability. Check SQLite runtime version/features on each supported OS.
- SQLite and UserNotifications do not share a transaction. Persist a desired-notification outbox record with the reminder change, register/update/cancel by stable identifier, and persist the observed outcome separately. A crash between steps must be reconcilable. Compare pending system requests against desired state on launch and other execution opportunities.
- Distinguish saved, scheduling-pending, scheduled, permission-blocked, and overdue. Successful notification registration is not evidence that a person saw an alert. Do not mark workflow side effects or user acknowledgement from an elapsed timer.
- Recover expired job leases with attempt IDs and deduplication. Reject results from old attempts or changed input revisions. Limit retries and preserve diagnostics without logging private text.
- Back up/export through SQLite's consistent backup mechanism or a carefully quiesced database, not by copying only the main `.sqlite` file while WAL is active. Design migrations and restore tests. Disk-full, malformed import, missing permissions, forced termination, and failed migrations must produce a visible recoverable state.
- App Sandbox is access confinement, not database encryption. Do not advertise encrypted-at-rest SQLite unless actually implemented and verified. Device-level FileVault and user backups are separate from app guarantees. Deletion must address data, pending notifications, artifacts, WAL/checkpoints, exports, and explain that external backups may persist.

## Signing, archive, and submission prerequisites

The future release owner must complete these steps. None were performed here.

1. Install an appropriate full Xcode version with the target SDK, with user approval. Confirm Apple's current upload requirements at release time [A12]. For local testing, use an explicit per-command developer-directory selection if necessary rather than silently changing global `xcode-select` configuration.
2. Decide minimum macOS and architecture coverage. macOS 13+ is the natural minimum if using `SMAppService`, but supported APIs and actual deployment target must be checked. Apple silicon testing alone does not establish Intel support; do not advertise universal support without building and testing it.
3. Create a native app project, bundle identifiers for app/three services/optional helper, capabilities, icons, category, versions, deployment targets, embed phases, and a real archive scheme. Include all executable code in the application bundle. Helper/service targets must not appear as extra standalone install products in the archive [A3].
4. User-controlled Developer Program enrollment and App Store Connect access are required for store distribution [A13, A14]. Verify authorized team/roles, legal agreements, appropriate identifiers, distribution signing identities, and provisioning profiles when applicable. Membership, tax/banking for paid distribution, and ownership/legal decisions cannot be assumed or supplied by this research.
5. Sign every nested code bundle correctly, using Xcode's managed signing/export flow where practical. Inspect final exported signatures and entitlements for every target, including absence of unintended `get-task-allow`, inheritance, network, and group privileges. Run installed/exported-bundle tests, not only Xcode Run tests.
6. Create a Release archive, perform Xcode's **Validate App**, resolve warnings/errors, and export without uploading until expressly authorized. Apple calls validation a **limited automated initial validation**, not full review approval [A13]. Test crash recovery, sandbox denial, helper lifecycle, accessibility, data import/export, and notification behavior in the distribution-like build.
7. Prepare an App Store Connect app record, unique build number, metadata, screenshots, support URL, privacy policy URL and in-app link, category/age rating, review contact and review notes. Explain deterministic workflows, consented background behavior, local-only operation, and how reviewers exercise all features. Answer privacy and export-compliance questions from actual shipped behavior. App Store Connect upload requires an authorized role and build processing [A12].
8. Only with explicit user authorization: upload, wait for processing, optionally test through TestFlight, select the build, submit for review, and choose release timing. Those are separate actions from building a package.

Use the Mac App Store distribution path for the store build. **Developer ID signing plus notarization is a separate direct-distribution path**, not a substitute for App Store submission/review [A13]. Hardened Runtime is recommended defense-in-depth for new code, but Apple's guide says it is not itself required for App Store apps [A3]. Do not misstate notarization or Hardened Runtime as universal App Store prerequisites.

## Privacy and disclosure

- Every app needs a privacy policy link in App Store Connect and an easily accessible in-app link. The policy must describe collection, use/sharing, retention/deletion, and withdrawing consent [A11, 5.1.1]. Even an entirely offline app is not exempt.
- App privacy answers cover third-party code as well as developer behavior. Apple defines collection for the privacy label in terms of transmission off the device that permits access beyond servicing a real-time request [A15]. A genuinely offline build with no telemetry, uploads, remote inference, or collecting SDKs may qualify for “Data Not Collected.” Verify the shipped dependency and data-flow inventory first. Local storage can still be sensitive and must be explained in the policy.
- No login is needed for the proposed local workflows. Avoid unnecessary account creation or permissions. If accounts are later added, account-deletion obligations change [A11].
- Explain that reminder previews can expose text on the lock screen or Notification Center. Default to minimal content or offer private previews. Logs and support exports should be redacted and user initiated.
- Inventory data flows and resources across **every target** and bundled dependency. Include privacy manifests where appropriate and generate/review the archive privacy report. Do not invent manifest contents before there is actual code to audit.
- **Native macOS nuance:** Apple's current privacy-manifest documentation says collected-data information applies on all platforms, but lists required-reason API reporting for iOS, iPadOS, tvOS, visionOS, and watchOS, not macOS [A16, A17]. Therefore do not blindly declare a native macOS `UserDefaults` call a required-reason submission blocker using iOS rules. Recheck applicable SDK/signature/manifest and platform requirements at release time. Listed third-party SDK requirements and privacy disclosure still need a dependency-specific review. Fingerprinting remains prohibited.
- No tracking is proposed. No contacts, calendar, microphone, screen recording, Accessibility, Full Disk Access, location, or notification permission should be requested merely because the product is called an assistant. User-created ARGUS reminders do not require access to Apple's Reminders/Calendar databases.

## Release gates and unresolved assumptions

| Gate | Evidence needed | Current status |
| --- | --- | --- |
| Full Xcode archive environment | Approved installation/path, SDK and release-compatible toolchain | Blocked locally: no Xcode found in checked application locations; CLT alone selected |
| Native app and release package | App project, all targets, archive/export validation | Not implemented by design |
| Three isolated workers | Three signed service identities/PIDs, one job per slot, crash/timeout/concurrency tests | Proposed, not demonstrated |
| Secret exclusion | Exported entitlements and negative synthetic Keychain/container tests | Proposed, not demonstrated |
| No shell/network | Code/dependency audit plus signed negative tests; precise threat-model agreement | Functional prohibition proposed; universal OS `exec` denial not established |
| After-Quit computation | Decide whether needed; approved helper prototype, IPC authentication and disabled-helper UX | Open product/architecture gate, not implied by system notifications |
| Notifications and recurrence | Sleep/wake/reboot/Focus/denial/DST/clock-change tests on supported macOS | API behavior documented; deadline reliability not guaranteed |
| Durable state | Crash/power/disk-full/migration/outbox/restore tests | Not implemented or tested |
| Privacy and legal | Policy, dependency inventory, accurate labels, export-compliance answers | Requires shipped implementation and owner decisions |
| Distribution authority | Membership, authorized roles, identifiers/signing, agreements | Unknown, deliberately not inspected |
| Store acceptance | Completed submission and Apple review | Cannot be promised |

No application or runtime tests were run because this deliverable is documentation only. Research validation consists of reading the cited official sources, checking local Xcode discovery as described, reviewing claim/limitation distinctions, checking citation-label completeness and whitespace, and checking that only this owned document was authored.

## Official Apple sources

All accessed 2026-09-17. Canonical URLs below correspond to the official pages consulted. Where Apple's documentation HTML required JavaScript, its official `https://developer.apple.com/tutorials/data/documentation/... .md` representation was read instead. Archive sources are labeled and their process-model claims require validation on the deployment OS.

- **[A1] App Sandbox:** https://developer.apple.com/documentation/security/app-sandbox
- **[A2] Creating XPC Services (Apple documentation archive):** https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html
- **[A3] Embedding a command-line tool in a sandboxed app:** https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app
- **[A4] Network client entitlement:** https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client
- **[A5] Sharing access to Keychain items among a collection of apps:** https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps
- **[A6] Scheduling a notification locally:** https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
- **[A7] Asking permission to use notifications:** https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
- **[A8] NSBackgroundActivityScheduler:** https://developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler
- **[A9] SMAppService:** https://developer.apple.com/documentation/servicemanagement/smappservice
- **[A10] SMAppService.register():** https://developer.apple.com/documentation/servicemanagement/smappservice/register()
- **[A11] App Review Guidelines, especially 2.4.5, 2.5.1, 2.5.2 and 5.1.1:** https://developer.apple.com/app-store/review/guidelines/
- **[A12] App Store Connect: Upload builds:** https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- **[A13] Distributing your app for beta testing and releases:** https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
- **[A14] Developer Program enrollment:** https://developer.apple.com/programs/enroll/
- **[A15] App privacy details:** https://developer.apple.com/app-store/app-privacy-details/
- **[A16] Privacy manifest files:** https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- **[A17] Describing use of required reason API:** https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
