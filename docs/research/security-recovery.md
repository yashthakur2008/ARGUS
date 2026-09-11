# ARGUS security and recovery design

Status: supporting security/recovery analysis, not the canonical product specification, implementation, or security-test evidence. Date: 2026-09-17. **The canonical specification and roadmap under `docs/superpowers` govern product requirements and final schemas.** Where this document proposes narrower defaults or simplified record shapes, defer to that specification: three concurrent isolated workers are required, prompt records include tags/version/history and the canonical metadata, sensitive bodies are encrypted rather than placed in plaintext FTS, and optional replaceable ElevenLabs TTS is permitted. The schemas below specify security/recovery mechanics and are not a replacement for canonical domain schemas. Repository evidence at initial inspection: `README.md` contained only `# ARGUS`.

## 1. Decision and smallest coherent model

Build a deterministic local application, not an autonomous agent. There is no runtime LLM, planner, prompt execution, model download, plug-in system, shell, email, arbitrary network, purchase operation, recursive worker creation, or discovery of unrelated files or secrets. Text that looks like instructions remains text.

Use SwiftUI for presentation, Foundation for calendar and typed data, one app-owned SQLite database, Security/Keychain for keys, UserNotifications for local alerts, and three distinct bundled sandboxed XPC services sharing one reviewed source implementation. The host is the sole authority and database writer. Support up to three concurrent isolated worker processes with separately validated signed identities. Three XPC connections do not necessarily mean three processes. Count live and unconfirmed-live services toward the limit. No third-party orchestration framework, background daemon, shared database container, or unbounded queue.

The three-service signed prototype is a release prerequisite, not a reason to quietly reduce the product requirement to one worker.

Three approaches considered:

| Approach | Benefit | Cost / decision |
|---|---|---|
| Everything inside the app | Smallest packaging and fewest IPC races | No worker fault boundary. Keep trusted SQLite search here, but separate untrusted text transformation. |
| Sandboxed host plus narrow XPC services | Crash containment and potential OS-enforced privilege separation | Selected with three distinct service bundles sharing reviewed source. Validate actual signed entitlements and access, not merely process IDs. |
| Generic process pool / agent framework | Flexible task routing | Rejected. Larger authority surface, unnecessary scheduling machinery, process isolation alone is not least privilege. |

The three default job kinds are **resolve preview**, **search prompts**, and **deadline briefing**. All produce local, inert results. They never execute the resolved prompt or trigger another job from its contents. Local editing, scheduling, export, deletion, and job controls are explicit UI commands, not worker tools.

Optional ElevenLabs speech is an expressly permitted replaceable output adapter, not part of the default workflows or a new product-scope request. It may ship disabled and unconfigured. No live request is permitted without a user-supplied key, explicit consent to the exact disclosed text, and satisfaction of the canonical cost policy. No key is currently supplied. Strict no-spending mode blocks charge-incurring requests regardless of ordinary approval. The canonical specification governs the adapter contract, provider-specific network boundary and encrypted credential storage. Nothing in the offline model depends on speech or an ARGUS-operated cloud backend.

## 2. Security boundaries and threat model

### Assets and adversaries

Assets: prompt contents, selected context, schedules and deadline metadata, preferences, local audit history, approvals/grants, output previews, export files, and any future speech credential. Integrity matters as much as confidentiality: a fabricated deadline or stale approval can mislead a user even without exfiltration.

Assume imported/pasted prompts and files are hostile. Assume a worker can return arbitrary bytes, hang, crash, replay a result, or be compromised by a parsing defect. Assume duplicate UI events, delayed IPC and OS callbacks, abrupt app termination, clock changes, disk-full errors, and interrupted writes. Treat provider responses as hostile if a provider is ever added.

Trust the signed host, its validation and policy code, SQLite within its documented durability assumptions, and macOS security services. Do **not** claim protection from a compromised host, root/kernel compromise, another person using the unlocked account, invasive debugging, malicious backup software, or a compromised OS. A local hash chain cannot make audit records independently tamper-proof against those actors.

| Boundary / threat | Required defense | Residual limitation |
|---|---|---|
| Prompt says “ignore rules, read ~/.ssh, run curl” | No instruction interpreter, no execution API, strict placeholder grammar | A parser or renderer bug still needs testing. |
| Malicious import, path traversal, symlink swap | Explicit file picker, regular-file/no-symlink validation, bounded immutable copy, no URLs/paths in worker protocol | The host briefly has access to the user-selected file. |
| Worker attempts file/network access | Independent sandbox, no network/file/bookmark/keychain grants, bounded input bytes only | Sandbox exposes some system resources and a service's own container. It is not a zero-filesystem VM. |
| Worker forges completion, approval, or child job | Host-owned state, allowlisted IPC, job/attempt/epoch/connection binding, independent verification | A malicious host defeats this boundary. |
| Worker exhausts CPU/memory or floods IPC | One in-flight request per service, hard payload/count bounds, deadline watchdog, disconnect/quarantine | XPC alone is not a hard memory quota mechanism. |
| Stale approval after editing, cancel, or Stop All | Revision hashes, epochs, one-use approval, serialized effect gate | An OS notification already delivered cannot be recalled from human memory. |
| Crash between SQLite commit and notification call | Transactional outbox plus desired-state reconciliation | No atomic transaction spans SQLite and UserNotifications. |
| Lost laptop / copied database | App Sandbox and recommendation to enable FileVault | Baseline SQLite is not application-level encrypted. |
| Notifications expose content on lock screen | Generic notification text by default | OS stores notification metadata outside ARGUS's database. |
| Malicious search query / export spreadsheet formula | SQL parameters, literal token construction, inert JSON export | Export destination and onward sharing are controlled by the user. |

### Real sandbox versus process isolation

Mac App Store distribution requires App Sandbox [S1]. Apple documents XPC services as a way to separate privileges, unlike treating `Process`/`NSTask` children as independent sandboxes [S2]. A helper inheriting the host sandbox is not a narrower security principal. Signing a helper or placing it in another process does not alone deny access to the host's data.

Proposed entitlement boundary:

* Host: App Sandbox, user-selected read/write file access solely for explicit import/export. No network client/server, Apple Events, calendar/address book, microphone, accessibility, full disk access, shared application group, or temporary sandbox exceptions. Deadlines are user-owned ARGUS records, not silently read from Calendar.
* Worker: App Sandbox with an independent service configuration, no sandbox inheritance, no application group, no user-selected file entitlement/bookmarks, no network entitlement, no secret-bearing keychain access group, and no host database handles. Do not pass file descriptors, listener endpoints, URLs, bookmarks, or raw database connections over IPC.
* IPC: bundled service only, minimum typed method set (`compute`, `cancel`, replies). Validate peer identity against expected signed app/service identity using APIs available on the selected minimum macOS version. Never authenticate a peer merely by PID or claimed bundle name. Restrict decoded classes to bounded data objects, reject unknown protocol versions and tags, and prohibit dynamic object/class instantiation.
* Service contains no process-launch or service-discovery tool surface. Application-level “no child workers” is enforceable in the protocol. It is **not** proof that malicious native code can never invoke any process syscall. Sandbox containment tests must characterize what the chosen platform actually permits.

Release gate: run a signed, sandboxed build on every supported macOS version and prove that worker attempts to open the host DB/container, selected source path, sibling worker container, unrelated home files, host keychain item, network sockets, and unauthorized IPC fail. Test inherited handles/environment for leaks. Some system read access is normal. If cross-container denial cannot be demonstrated, describe the boundary as crash isolation only and do not ship with a claim of hostile-worker confidentiality. This is an implementation blocker, not something this document can prove.

## 3. Normative type model

The following is a language-neutral schema specification, not application code. All records use `schemaVersion = 1`. Unknown fields/tags/versions, duplicate keys, malformed UTF-8, overflow, and out-of-range values are errors. `?` means an explicit nullable field. `[]` is an ordered bounded list. No untyped `Any`, arbitrary JSON arguments, raw SQL, command strings, or user-specified URLs are permitted.

Primitives:

* `ID`: 128-bit random UUID, serialized as lowercase canonical UUID text. Entity IDs are distinct types, not interchangeable strings.
* `Revision`, `Epoch`, `Sequence`: nonnegative signed 64-bit integers, checked increment, never wrap.
* `Instant`: signed 64-bit Unix UTC milliseconds. Calendar computations additionally use the stored IANA zone. Execution timeouts use a monotonic clock, not `Instant`.
* `Digest`: SHA-256 over a domain label plus a versioned canonical encoding. Encoding is typed, length-prefixed UTF-8/bytes, fixed-width integers, explicit null tags, dictionary keys sorted by UTF-8 bytes, preserved array order. Never hash ambiguous concatenation or default Swift JSON output. Document text bytes are preserved, not silently normalized.
* `Ref`: `{kind: prompt|context|deadline|schedule|preferences|snapshot|result|audit, id: ID, revision: Revision, digest: Digest}`. Immutable entities use revision 0. Each command additionally allowlists reference kinds: resolve accepts prompt/context only, schedule removal accepts schedule only, and export/delete accept the explicit selected kinds.
* `Snapshot`: `{id: ID, refs: Ref[], contentDigest: Digest, capturedAt: Instant, algorithmVersion: 1}`. Its bounded immutable payload is local to that job. No lazy reread of a mutable external file.

### 3.1 Host commands

Every command is `{id: CommandID, issuedAt: Instant, body: CommandBody}`. The authenticated UI creates it, never a prompt or a worker. Persist a unique `CommandID` with request digest and bounded outcome for idempotence, not another copy of raw command content. Input bytes live only in retention-managed records/snapshots. Reusing an ID with different content is rejected. Imported backups cannot import executable commands.

`CommandBody` is exactly one of:

| Tag | Typed fields |
|---|---|
| `resolvePreview` | `prompt: Ref, bindings: Binding[], context: Ref[]` |
| `searchPrompts` | `query: Text[1..512 bytes], mode: literal\|fullText, limit: Int[1..100]` |
| `deadlineBriefing` | `asOf: Instant, throughExclusive: Instant, zone: IANAZone, includeOverdue: Bool` |
| `saveRecord` | `expected: Ref?, record: PromptRecord\|ContextRecord\|DeadlineRecord\|PreferencesRecord` |
| `proposeEffect` | `effect: Effect` |
| `decideApproval` | `approvalID: ID, expectedBinding: Digest, decision: approve\|deny` |
| `revokeApproval` | `approvalID: ID` |
| `controlJob` | `jobID: ID, expectedRevision: Revision, action: pause\|resume\|cancel\|retry\|restart, replacement: JobRequest?` |
| `stopAll` | no payload |
| `resumeSystem` | `expectedStopEpoch: Epoch` |

`JobRequest` is exactly the payload of `resolvePreview`, `searchPrompts`, or `deadlineBriefing`, including its tag. `replacement` is required only for Restart and forbidden for other controls. The host takes a new snapshot from that explicitly confirmed replacement. No old input is silently refreshed.

Record definitions:

* `PromptRecord = {id, title: Text[0..256 bytes], template: Text[0..65536 bytes]}`.
* `ContextRecord = {id, label: Text[0..256 bytes], text: Text[0..1048576 bytes], provenance: pasted|selectedFile}`. File paths are not stored as reusable authority. Import uses a transient picker-approved handle, not a file path supplied in text.
* `DeadlineRecord = {id, title: Text[1..256 bytes], dueAt: Instant, displayZone: IANAZone, status: open|done}`. Date-only input must be converted through an explicitly displayed local time and zone before save.
* `PreferencesRecord = {id: fixedSingletonID, displayZone: IANAZone, workerLimit: Int[1..3], auditDays: Int[1..365], previewDays: Int[0..30], genericNotifications: true, speech: disabled}`. Changing alert permissions is not a preference shortcut.
* `Binding = {name: ASCIIIdentifier[1..64], value: Text[0..65536 bytes]}`. Duplicate binding names are rejected. A name matches `[A-Za-z_][A-Za-z0-9_]*`.

Saving a record is authorized only by a direct editor action and optimistic revision check. It cannot enable a schedule or export/delete data. Changing any referenced revision invalidates outstanding affected approvals. The host assigns revisions, digests, timestamps, and provenance. A received record cannot assign them itself.

**Privacy precedence:** the canonical design encrypts sensitive bodies. The FTS/tokenization discussion below applies only to fields explicitly permitted in plaintext indexing by that design, never decrypted prompt bodies persisted into a plaintext FTS table. Body search must follow the canonical encrypted-search approach and unlock behavior. These simplified record definitions omit canonical tags, versions and history, which remain required.

### 3.2 Workflow semantics and bounds

**Resolve preview:** grammar is literal text and `{{identifier}}` substitution only. No expressions, recursion, template includes, environment lookup, URL expansion, implicit clipboard reads, or automatic context selection. Bindings are substituted once. Inserted values containing `{{...}}` are not expanded. Context is an ordered list of explicitly selected snapshots appended as labeled plain text, not authority. Malformed/unbalanced double braces produce invalidInput. A syntactically valid placeholder with no supplied binding produces `waiting(missingInput)` with the exact names. Extra unused bindings are rejected rather than silently carrying unrelated context. Changing input creates a successor job, never edits a running snapshot. Render using native plain text, not a WebView or active Markdown links. Display source revisions and missing input clearly.

**Search:** literal mode is an exact case-sensitive Unicode scalar substring search over stored title/template, with no regex or wildcard semantics. Full-text mode uses SQLite FTS5 `unicode61 remove_diacritics 2`, default token character categories and no custom token/separator options, no semantic/embedding search. User input is converted to escaped quoted tokens combined by AND, never passed as raw MATCH syntax. Use bound SQL parameters even for this generated expression. All-token-empty input yields no matches. Order full-text hits by ascending `bm25` with title/template weights 1.0/1.0, then stable prompt UUID bytes. Order literal hits by prompt UUID bytes. Freeze catalog revision and query semantics in the snapshot. Rebuilding a derived FTS index is safe. Absence of FTS5 in a deployment SQLite build is a release blocker for full-text mode, not a reason to silently relabel literal search [S7].

**Briefing:** select open deadline snapshots with `dueAt < throughExclusive` and, unless `includeOverdue`, `dueAt >= asOf`. Require `throughExclusive > asOf` and interval at most 366 days. “Overdue” means `dueAt < asOf`, “due now” means equality. Sort by `dueAt`, then UUID bytes. Format with explicit Gregorian calendar, stored zone and versioned deterministic formatter. No inferred importance, inferred dates, or generated recommendations. Reproducibility is defined over identical snapshots, `asOf`, zone rules, and algorithm/formatter version, not arbitrary future OS calendar databases.

Hard bounds: 10 MiB total job snapshot, 1 MiB preview/result, 32 context references, 256 bindings, 10,000 deadline rows, 100 search hits, 100 queued jobs, and one request per worker. Exceeding a bound fails visibly with `limitExceeded`, never silently truncates a briefing. Search `limit` is intentional and total matching count is displayed. Keep payload bounds at decode time, not after unbounded allocation. Worker deadline is 30 monotonic seconds per attempt, a cancel grace target of 2 seconds, and no automatic replacement while an old service's liveness is unresolved. These are application policy targets, not OS real-time guarantees.

### 3.3 Jobs, attempts and results

```
Job = {
  id: JobID, commandID: CommandID, parentJobID: JobID?,
  kind: resolvePreview | searchPrompts | deadlineBriefing,
  snapshotID: ID, inputDigest: Digest, algorithmVersion: 1,
  state: queued | working | waiting | completed | failed | cancelled,
  wait: WaitReason?, failure: FailureCode?,
  revision: Revision, stopEpoch: Epoch, jobEpoch: Epoch,
  currentAttempt: AttemptID?, resultID: ResultID?,
  createdAt: Instant, updatedAt: Instant
}
WaitReason = missingInput {names: Identifier[]}
           | paused | recoveryReview | resourceUnavailable
FailureCode = invalidInput | limitExceeded | timeout | workerCrashed
            | verificationFailed | sourceUnavailable | storageFailure
Attempt = {
  id: AttemptID, jobID: JobID, ordinal: Int[1..3],
  ownerSession: ID, connectionNonce: ID, workerSlot: Int[0..2]?,
  stopEpoch: Epoch, jobEpoch: Epoch, inputDigest: Digest,
  status: running | verified | failed | abandoned,
  startedAt: Instant, endedAt: Instant?, failure: FailureCode?
}
WorkerRequest = {
  schemaVersion: 1, jobID: JobID, attemptID: AttemptID,
  connectionNonce: ID, stopEpoch: Epoch, jobEpoch: Epoch,
  inputDigest: Digest, algorithmVersion: 1,
  payload: resolve {prompt: PromptRecord, promptRef: Ref, bindings: Binding[], context: {ref: Ref, record: ContextRecord}[]}
         | briefing {asOf: Instant, throughExclusive: Instant, zone: IANAZone, includeOverdue: Bool, deadlines: {ref: Ref, record: DeadlineRecord}[]}
}
WorkerCancel = {schemaVersion: 1, jobID: JobID, attemptID: AttemptID, connectionNonce: ID, stopEpoch: Epoch, jobEpoch: Epoch}
WorkerReply = {
  schemaVersion: 1, jobID: JobID, attemptID: AttemptID,
  connectionNonce: ID, stopEpoch: Epoch, jobEpoch: Epoch,
  inputDigest: Digest, algorithmVersion: 1,
  output: PreviewOutput | BriefingOutput
}
PreviewOutput = {text: BoundedText, usedRefs: Ref[], unresolved: Identifier[]}
BriefingOutput = {rows: {deadlineRef: Ref, dueAt: Instant, category: overdue|dueNow|upcoming}[]}
SearchOutput = {catalogRevision: Revision, hits: {promptRef: Ref, matchedFields: (title|template)[]}[], total: Int}
VerifiedResult = {
  id: ResultID, jobID: JobID, attemptID: AttemptID,
  inputDigest: Digest, outputDigest: Digest, payloadState: present|expired,
  output: (PreviewOutput|BriefingOutput|SearchOutput)?,
  verifierVersion: 1, verifiedAt: Instant
}
```

`workerSlot = null` means a host-executed SQLite search attempt, which does not claim a worker slot. The host assigns a fresh nonce even to local attempts for a uniform result-binding model. `wait` is non-null exactly in waiting state, `failure` exactly in failed state, and `resultID` exactly in completed state. `currentAttempt` points to the active attempt only while working and is cleared otherwise. The attempt's original epochs/nonces remain immutable for audit. Consume the one-use compute grant in the dispatch transaction and never redispatch the same attempt after uncertain IPC delivery. Workers never receive a search database or catalog-wide authority. `SearchOutput` is created and checked in one host read transaction against the frozen catalog revision. Rendering uses the frozen matched text stored with the snapshot. No result has a free-form “verified: true” field controlled by the worker. Results enter storage with payloadState=present and non-null output. Retention may erase output and set payloadState=expired while retaining the result identity/digests, preserving completed-job referential integrity. Deleting metadata too requires an explicit cascade including the referring job. Search Retry/Resume requires the original catalog revision still to exist. Version 1 keeps no historical FTS indexes, so a catalog change requires Restart rather than querying a new catalog under an old snapshot.

Host verifier checks envelope/connection identity, all digests and epochs, bounded fields, allowed references and complete row sets. It recomputes substitutions and deadline selection/order from trusted snapshots. A small deterministic recomputation is cheaper than trusting self-reported success. It compares exact output, not merely a worker-generated checksum. A failure is never displayed as completed. “Verified” means matches the deterministic algorithm and input snapshot, not that a user's source text or deadline is true. Result insertion, attempt verification, job completion and audit insertion are one SQLite transaction guarded by the current attempt and revision.

### 3.4 Capabilities and approvals

Workers have no effect tools. A grant is a host ledger entry, not a bearer string that a worker can redeem elsewhere:

```
Grant = {
  id: ID, subject: hostSession(ID)|attempt(AttemptID),
  operation: computePreview|computeBriefing|searchLibrary|applySchedule|exportData|deleteData,
  resources: {manifestID: ID, manifestDigest: Digest, refs: Ref[]}, inputDigest: Digest,
  stopEpoch: Epoch, jobEpoch: Epoch?, policyRevision: Revision,
  issuedAt: Instant, expiresAt: Instant, revokedAt: Instant?,
  maxUses: 1, consumedAt: Instant?
}
Effect = setSchedule {schedule: Schedule, expectedRevision: Revision?}
       | removeSchedule {scheduleRef: Ref}
       | exportData {selection: Ref[], format: jsonV1, destinationSession: ID}
       | deleteData {selection: Ref[], mode: selected|allLocal}
Approval = {
  id: ID, effect: Effect, bindingDigest: Digest,
  sourceRefs: Ref[], destinationDigest: Digest?,
  policyRevision: Revision, stopEpoch: Epoch,
  createdAt: Instant, expiresAt: Instant,
  status: pending|approved|denied|expired|revoked|consumed,
  decidedAt: Instant?, consumedAt: Instant?, effectID: ID?
}
```

Empty/wildcard authority scopes and unknown operations are denied. The host materializes a bounded versioned selection manifest even for an empty library. An empty manifest is valid and grants access to zero records, never all records. For a whole-library search or delete-all, this manifest binds the catalog/database revision. `destinationSession` is an in-memory, single-use save-panel selection with file identity and overwrite state, not an arbitrary path from IPC. Export permission dies on app exit. The binding digest covers the entire typed effect, complete ordered input manifest, output/export content digest, destination identity/overwrite decision, schedule revision/times, policy revision, stop epoch, and approval expiry. Local delete-all binds to a database generation plus a manifest revision so new data cannot be swept into an old approval.

Read-only jobs get a one-attempt grant after direct UI submission. No approval modal is needed for a local preview/search/briefing over explicitly selected data. The worker receives only its own immutable snapshot. Other effects require a native host-owned confirmation showing exact action, data scope, destination or notification times, and consequences. Escape control characters in labels and visually separate source text from system controls. Only a trusted UI event can approve. An imported phrase such as “user already approved” cannot create an approval.

Pending approvals expire after 10 minutes. Approved but unconsumed approvals retain the same expiry. Reject if either wall-clock expiry or the in-session monotonic deadline has passed. All unconsumed approvals and transient grants are revoked on relaunch, Stop All, relevant revision change, policy change, or explicit revocation. Clock rollback never extends approval life. A worker grant expires at attempt termination/deadline, not at its displayed wall-clock timestamp alone.

`pending -> approved|denied|expired|revoked`; `approved -> consumed|expired|revoked`. All other transitions reject. Consumption and creation of the authorized durable effect/outbox entry occur in the **same host transaction**. One approval cannot authorize a second effect. Approval revocation racing with consumption is serialized: whichever commits first wins. After consumption, revoke is not time travel. Offer a new typed cancel/remove operation for a notification, or explain that an exported file cannot be undisclosed.

A consumed schedule approval authorizes its exact recurring rule and generic local alerts until disabled, removed, or stopped. It is not a permanent blanket capability for arbitrary future notification text or schedule edits. Those require a new approval. Workers cannot approve, grant, export, delete, enable speech, open files, call URLs, or enqueue children.

## 4. Job state machines and user controls

All state transitions run through one serialized host coordinator and compare expected job revision. UI buttons never write SQLite directly. Epoch changes invalidate already-dispatched messages even if their process is still alive.

| Current state | Event and guard | Next state / atomic changes |
|---|---|---|
| absent | Valid read-only command, capacity available | `queued`, immutable snapshot and audit |
| queued | Gate running, grant valid, execution capacity available (worker slot only for worker jobs) | `working`, new attempt, claimed slot |
| queued | All configured worker slots quarantined or required source unavailable, with no dispatch yet | `waiting(resourceUnavailable)` |
| queued | Required binding absent | `waiting(missingInput)` |
| working | Verified result, matching attempt/epochs | `completed`, result and audit in same transaction |
| working | Timeout/crash/invalid result | `failed`, close attempt and invalidate job epoch |
| queued/working | Pause | `waiting(paused)`, increment job epoch, abandon attempt and cancel worker |
| waiting(paused/recoveryReview/resourceUnavailable) | Explicit Resume, prerequisites valid, system running | `queued`, same snapshot, new attempt on next dispatch |
| waiting(missingInput) | User supplies changed input | Cancel original and create linked successor command/job |
| queued/working/waiting | Cancel | `cancelled`, increment job epoch, revoke attempt grant |
| failed | Retry, unchanged snapshot/policy, attempts < 3 | `queued`, preserve job ID and inputs, next attempt ordinal |
| any existing state | Restart | Create new linked job from newly confirmed inputs; cancel original if nonterminal |
| completed/cancelled | Retry/Resume | Rejected. Use Restart. |
| any terminal state | Late worker result | Discard and metadata-only audit, no state resurrection |

Missing input is not a partial success. Pausing is logical cancellation of an attempt, not suspension of a native process or persistence of a stack/checkpoint. Resume recomputes from the immutable snapshot. Retry means same inputs, not “try a different action.” Restart means new job ID, new input snapshot and new grants. At most three attempts may ever start for a job, including paused or abandoned attempts. Once exhausted, Resume/Retry is rejected with “Restart required.” There is no automatic infinite retry on any failure.

For already completed jobs, Pause/Cancel is a no-op reported as “already completed.” Deleting a result is a separate explicit delete action. A blocked coordinator/storage failure is displayed as such, never reported as a successful persistent cancel.

### Global Stop All and race protections

Persistent singleton: `SystemControl = {mode: running|stopped, stopEpoch: Epoch, databaseGeneration: ID, policyRevision: Revision}`. The process also maintains a fail-closed in-memory dispatch latch. The UI sets this latch immediately on Stop All before waiting for any database operation.

Stop All then, through the coordinator:

1. In one transaction set `mode=stopped`, increment `stopEpoch`, cancel all nonterminal jobs, abandon running attempts, revoke unused grants/approvals, disable all schedules, and write desired notification removals and audit. Previously completed results remain readable.
2. Close worker connections and request cooperative cancellation. Reject every old-epoch reply regardless of cancel acknowledgement. Do not release a worker slot for a replacement merely because a timeout fired. Confirm termination or quarantine the slot. XPC connection invalidation is not a guaranteed synchronous process kill [S2].
3. Stop any local playback and enqueue removal of pending and delivered ARGUS notifications. Reconciliation continues in stopped mode for **removals only**.
4. Show “Stopped” only after the persistent stop transaction succeeds. Show separate “notification cleanup pending” or “worker shutdown unconfirmed” status where applicable. If the transaction fails, the in-memory latch remains closed, attempt best-effort OS removal, and display “Stop not durably saved.” Startup also starts latched closed until recovery completes.

The effect dispatcher and Stop All share a serial non-reentrant gate. A Swift actor's isolation alone is insufficient if a permission check is followed by an `await` and then a side effect. Claim/check the epoch and initiate the OS call without an intervening suspension on this gate. Asynchronous completion is a separate event that rechecks current epoch before committing its result. SQLite transactions are never held open across OS calls.

If an OS add call was initiated **before** Stop All linearized but completes after it, its completion must request removal of that identifier instead of recording current acceptance. Reconciliation independently removes it even if that callback is lost. Once the stop transaction commits, no new old-epoch calls may be initiated. No distributed atomicity is claimed: notifications already in the system's delivery pipeline may appear, and notification text already viewed cannot be erased. “Stop All” is a revocation barrier plus cleanup, not a promise to undo external effects.

Resume System changes the mode only after explicit confirmation of the expected stop epoch. It does not resurrect cancelled jobs, old grants, approvals or disabled schedules. Re-enable a schedule with a fresh approval. Cleanup of old generations must finish or remain prominently blocked before scheduling new ones.

## 5. SQLite durability and outbox

Use one private local database. The minimum tables are `system_control`, `records`, derived `prompt_fts`, `snapshots`, `commands`, `jobs`, `attempts`, `results`, `grants`, `approvals`, `effects`, `schedules`, `occurrences`, `outbox`, and `audit`. All payload columns decode through the versioned types above. `AuditEvent = {id: ID, sequence: Sequence, at: Instant, event: commandAccepted|stateChanged|approvalChanged|grantChanged|effectChanged|resultRejected|reconciled|retentionApplied|recovery, subjectID: ID?, previousState: Text[0..32 bytes]?, nextState: Text[0..32 bytes]?, reason: FailureCode?, stopEpoch: Epoch, policyRevision: Revision, algorithmVersion: 1, bindingDigest: Digest?}`. State strings must belong to the subject type's declared enum, never arbitrary input text. Sequence is assigned by the host transaction. SQL constraints enforce state tags, nullability, foreign keys, positive bounds, unique command IDs, unique `(jobID, ordinal)`, one result per job, and one occurrence per `(scheduleID, scheduleRevision, localDate, foldChoice)`.

Choose rollback journal `DELETE` with `synchronous=EXTRA`, `fullfsync=ON` on macOS, `foreign_keys=ON`, short transactions and a bounded busy timeout. With one writer and small bounded datasets, this is simpler than introducing WAL and checkpoint management. Verify PRAGMA results and target SQLite support instead of assuming they took effect [S3, S8]. A derived FTS table is updated transactionally with its prompt record. Never turn off journaling for performance.

If later profiling justifies WAL, explicitly migrate and test `synchronous=FULL`, backup handling for `-wal`/`-shm`, checkpoint starvation and current SQLite advisories [S4]. Do not copy only the main SQLite file while it is live. Exports are logical JSON snapshots inside a read transaction, not database-file copies. SQLite atomicity covers its own transaction under documented filesystem assumptions, not an OS notification, Keychain item, or export file [S3].

### Outbox schema and protocol

```
Outbox = {
  id: ID, effectID: ID?, occurrenceID: ID?,
  origin: approvedEffect(ID)|stopCommand(CommandID)|reconciliation(ID),
  kind: ensureNotification | removeNotification,
  requestID: Text, scheduleRevision: Revision?, stopEpoch: Epoch,
  desiredDigest: Digest?,
  status: pending|inFlight|acknowledged|superseded|blocked,
  ownerSession: ID?, attemptCount: Int[0..3],
  nextAttemptAt: Instant?, lastError: permissionDenied|transient|storageFailure|invalidRequest|null
}
Occurrence = {
  id: ID, scheduleID: ID, scheduleRevision: Revision,
  localDate: GregorianDate, foldChoice: first,
  dueAt: Instant, resolvedOffsetSeconds: Int,
  requestID: Text, desired: scheduled|removed,
  observation: unknown|pendingObserved|deliveredObserved|notObserved,
  lastObservedAt: Instant?, acknowledgedByUserAt: Instant?
}
```

Only removal rows may omit `effectID`, and only for trusted Stop/reconciliation cleanup. An ensure row must trace to its approved schedule effect. Cleanup never requires a fresh approval that Stop itself would invalidate.

Identifier format is `argus.v1.<databaseGeneration>.<scheduleID>.<revision>.<localDate>`. It contains no title, context, or other private content. Only one logical occurrence exists for a fold. No fresh random request ID on retry.

1. Schedule approval consumption, schedule/occurrence mutations, and required outbox inserts commit together. The unique desired operation per request ID/revision prevents duplicate logical effects.
2. Dispatcher claims a pending row in a short transaction and marks it in-flight with the current app session. Recheck schedule revision, desired state, permission and stop epoch at the serial effect gate immediately before calling UserNotifications. Stale adds become superseded, never “best effort” sends.
3. On add success, record acknowledged only if still desired at the same epoch. Acknowledged means the API accepted scheduling, **not** delivered, noticed or read. On stale success, enqueue removal. On errors, permission denial is blocked until user action; transient errors get at most three calls total: the initial call and two retries delayed 1 and 5 seconds while running. After exhaustion, show blocked and offer retry via reconciliation, not a busy loop.
4. On launch, wake, clock/time-zone change, permission change, foreground entry and schedule edits, query pending and delivered requests [S5]. Compare only ARGUS's namespace with authoritative current desired state. Remove stale/disabled IDs, replace mismatched current payload/trigger, and add missing **future** desired requests using the same ID. Serialize remove/replace/add per identifier and wait for completion or a fresh observation before declaring convergence.
5. A process crash abandons all previous-session in-flight claims. Reconcile observations before resubmitting. Pending reads are observations, not a lock against OS delivery. After a due time, an absent request means unknown, not proof of non-delivery, so never replay that alert automatically.

A notification's `userInfo` contains only opaque occurrence identity and schema version. Notification interactions validate the current generation/revision and open local UI. They cannot approve effects, run prompts or revive stopped jobs. Delivery callbacks are deduplicated by occurrence ID. Absence from the delivered list can mean the user cleared it, so absence cannot establish “never delivered.”

### Effect commitment and Stop ordering

`EffectRecord = {id: ID, approvalID: ID, kind: setSchedule|removeSchedule|exportData|deleteData, bindingDigest: Digest, stopEpoch: Epoch, status: prepared|initiated|erasePending|completed|cancelled|uncertain|failed, updatedAt: Instant, failure: FailureCode?}`. Store it in `effects`, uniquely keyed by approval ID. Effects are not compute jobs. Approval consumption creates exactly one logical effect record, not proof of successful external execution. Schedule/delete mutations can commit transactionally with consumption. Export persists `prepared`, then passes the same serial effect gate immediately before publication. Stop cancels any still-prepared export and cleans its ARGUS-owned temporary bytes. An already-initiated atomic publication may finish and must be shown as completed or uncertain, not falsely cancelled. A relaunch never automatically republishes an uncertain export. Cleanup/removal effects may proceed while stopped, but cannot add notifications, export bytes or start computation. `erasePending` is a durable delete effect phase, not an unconstrained global Boolean.

### Crash recovery and corrupt storage

On every app launch: close dispatch latch; open SQLite and allow journal recovery; validate schema/migration and integrity as appropriate; create a fresh host session; revoke old approvals/grants; move previous `working` jobs to `waiting(recoveryReview)` with abandoned attempts; preserve completed/failed/cancelled states; reconcile notifications before reopening dispatch. Queued read-only jobs become `waiting(recoveryReview)` too. The user explicitly chooses Resume. This prevents an abrupt termination from silently restarting old work. Previously approved schedules may reconcile when persistent mode is running because their durable authorization is distinct from expired one-use approvals.

Crash after completion commit but before UI update shows the saved result on next launch. Crash before commit shows no completed result. Crash after notification add but before acknowledgement is reconciled using its stable ID, not duplicated. Crash during migration rolls back or uses a verified local pre-migration backup, never silently creates an empty replacement. Corruption causes a read-only recovery screen with scheduling disabled. Do not wipe data automatically. Disk-full/failed audit write rolls back its associated state transition. Notification removals may still be attempted as safety cleanup, with the inability to persist recorded visibly when possible.

## 6. Calendar, DST and missed alerts

```
Schedule = {
  id: ID, enabled: Bool,
  rule: once {dueAt: Instant, zone: IANAZone}
      | daily {hour: Int[0..23], minute: Int[0..59], zone: IANAZone},
  startInclusive: Instant, endExclusive: Instant?,
  gapPolicy: nextValidTime, foldPolicy: first,
  missedPolicy: inboxSummaryNoReplay,
  content: genericReminder
}
```

Keep version 1 to one-shot and daily rules. No arbitrary cron, scripting or locale-dependent natural-language recurrence. Use Gregorian calendar and an explicit IANA zone. A schedule retains its creation zone when the machine travels. Changing its zone is an edit with a new revision and approval. Apple Calendar exposes explicit matching and repeated-time policies [S6]. Set them rather than trusting defaults.

For daily 02:30 in `America/Los_Angeles` on 2026-03-08, the nonexistent time maps to the next valid wall time, 03:00 PDT, not 03:30. For daily 01:30 on 2026-11-01, use the first occurrence, 01:30 PDT, not the second PST occurrence. Store the actual UTC instant, zone, local date and offset for each occurrence. A one-shot date picker must display the resolved offset and ambiguous/gap adjustment before approval. A time-zone database update that changes future instants invalidates and replaces affected occurrences under the same approved wall-clock rule, with an audit entry and visible adjustment. It never replays an already elapsed occurrence.

Materialize nonrepeating notifications for the next 30 days, at most 32 total pending ARGUS requests, ordered by due time then schedule ID. This is a conservative application cap, not an assertion of a universal macOS quota. An unmaterialized occurrence remains visible as “not yet submitted to macOS.” Refill on launch/wake/foreground. Do not promise indefinite alerts after the app has been closed beyond that horizon. No scheduled job will run just because a local notification fires. UserNotifications can deliver previously scheduled alerts without the app running, but it is not a general guaranteed job scheduler [S5].

At each reconciliation, mark elapsed occurrences without reliable delivery evidence as `notObserved`, and show one deduplicated in-app missed/unknown summary. Do not send a catch-up burst or claim an alert was definitely missed. Sleep, power-off, Focus, notification permission, clock jumps and OS policy may delay or suppress user-visible alerts. Existing pending notifications may already have been shown on wake, so the in-app summary is not another system alert. Wall-clock changes recompute future occurrences, while monotonic attempt/approval deadlines do not move backward.

Briefings are computed only on explicit user request or an already-running authorized local workflow. A reminder may say “Open ARGUS to review deadlines,” never present a stale precomputed briefing as current.

## 7. Privacy, export, deletion and encryption

**Default collection:** none outside the device. No telemetry SDK, remote crash submission, cloud sync, clipboard polling, directory crawling, Calendar import, or background audio capture. No secret scans. Raw prompts/context/results never enter system logs. Audit records contain event sequence, time, IDs, state changes, policy/algorithm versions, bounded reason codes and digests, not full content, file paths, provider keys or notification text. Digests of low-entropy content can still disclose information by guessing, so treat audit as private data.

**Retention:** prompts/deadlines/schedules/preferences persist until deletion. Keep preview/snapshot payloads seven days by default, configurable to 0–30 days, and audit metadata 30 days by default, configurable to 1–365. Active jobs and pending approvals pin needed snapshots, but cancellation/expiry removes that pin. Retention-expired jobs cannot be retried using missing snapshots. They require Restart. Search FTS data is a derived private copy subject to the same deletion lifecycle.

**Export:** explicit save-panel destination, exact selection/content digest and overwrite warning in approval. Export versioned UTF-8 JSON with records, zone semantics and optional selected audit metadata. Exclude credentials, security bookmarks, approval/grant authority and resumable job/outbox state. Create a local temporary file in the authorized destination and atomically replace only the approved destination after checking identity/overwrite conditions. Never automatically overwrite a changed destination. Verify exported byte digest and surface permission/storage failures. A destination capability is invalid after relaunch. If a crash leaves a completed or partial export with uncertain status, report that uncertainty and do not automatically export again. External copies are outside ARGUS's deletion control.

**Delete selected:** show linked schedules/results/context use. Require an explicit cascade manifest rather than silently removing unrelated records. In one transaction revoke associated approvals/grants, cancel affected jobs, remove records and FTS rows, and enqueue notification removals. Audit only noncontent tombstone IDs when retention is enabled. A deleted source is not retained forever by hidden snapshots. Remove linked payload snapshots/results after jobs release them, with bounded cleanup and visible failure status.

**Delete all local data:** validate and consume the confirmed delete-all approval in the same transaction that executes the Stop All state changes and writes `erasePending`. Do not run Stop All first as a separate command, because that would revoke the very approval needed for deletion. This consumed effect is authorized only for cleanup of the bound database generation, even while stopped. Before removing the database, atomically write and durably synchronize a minimal deletion manifest in the app's private storage containing only effect ID, notification namespace/generation and remaining cleanup categories. If a crash occurs before manifest creation, the database's `erasePending` record resumes that step. If both records exist, the deletion effect ID must agree. Never delete the database before the manifest is durable. Relaunch checks for this manifest before opening or recreating normal data stores. Remove pending/delivered notifications, all ARGUS-owned database/journal/temp/cache/backup files, and any ARGUS-owned future provider credentials. Never enumerate or delete unrelated keychain items/files. Then recreate an empty stopped database with a new generation, remove the deletion manifest only after reconciliation, and ask explicitly before enabling workflows. Deletion progress is idempotent and resumable. If notification cleanup cannot be confirmed, retain only the minimal manifest and disclose the pending step. Delete-all removes audit history too.

Deleting rows, `secure_delete`, VACUUM or removing files is not a guarantee of forensic erasure from APFS snapshots, SSD wear-leveling, Time Machine, exports or other backups. SQLite documents `secure_delete` limitations, including virtual-table shadow data [S8]. Inform users how to manage their own backups. Never claim a deleted notification or exported document can be recalled from a person who saw it.

**Encryption tradeoffs, not the selected storage policy:** canonical encrypted bodies take precedence. App Sandbox and FileVault complement that encryption, they do not replace it [S9]. Ordinary SQLite does not itself encrypt fields. Keychain protects encryption keys and a future provider credential at rest, but not against code already authorized to read them [S10]. No provider key is supplied. Use Data Protection Keychain for every add/read/update/delete operation with `kSecUseDataProtectionKeychain=true`, a broker-private access group absent from all workers, and `kSecAttrSynchronizable=false`. Do not rely on legacy macOS Keychain behavior to enforce access-group separation [S12]. Workers have no shared app/keychain groups. Signed cross-process denial tests remain mandatory.

Application-level encryption follows the canonical design and must not be replaced by custom cryptography. Encrypting only prompt blobs leaves any deliberately unencrypted titles, schedule metadata, indexes and access patterns exposed. Indexing decrypted bodies into persistent plaintext FTS defeats body confidentiality. Whole-database encryption is an alternative requiring a reviewed SQLite encryption implementation and key lifecycle, an added dependency. A key held in the same unlocked account protects some offline theft scenarios but not host compromise. A user passphrase offers a different boundary at the cost of no unattended access and no password reset/recovery guarantee. Cryptographic erasure additionally requires proof that keys and plaintext copies were not backed up. No custom cryptography or “AES means secure” claim.

## 8. Acceptance and adversarial test matrix

These are required future tests, **not tests executed in this design task**. Use deterministic injected clocks, UUIDs, calendar fixtures, temporary isolated stores, controlled fake notification adapters for exact interleavings, and real signed macOS builds for platform boundaries. Stub success cannot satisfy sandbox, notification or crash-durability release gates.

| ID | Exercise / failure injection | Observable acceptance result |
|---|---|---|
| A01 | Resolve prompt containing shell syntax, “ignore policy,” credential paths and tool JSON | Inert text preview. Zero process/network/file-opening effects and no new command. |
| A02 | Binding contains another placeholder; repeated/unknown/malformed variables; Unicode controls | Single-pass substitution, missing-input wait or explicit parse error. Confirmation UI cannot be spoofed by control characters. |
| A03 | Import `../` names, symlink swap, FIFO/device/package, oversized file, invalid UTF-8 | Host rejects unsupported source before blocking/unbounded read. Worker receives no path or handle. Source handle identity is checked around bounded snapshot read. |
| A04 | Search quotes, SQL injection, FTS operators, wildcard-looking text, empty tokens | No SQL/MATCH interpretation beyond specified token semantics. Stable fixture hits/order/count. |
| A05 | Briefing includes equal-time deadlines, overdue, completed and range-boundary rows | Exact fixture selection/category/order, including `dueAt == throughExclusive` exclusion. |
| A06 | Worker returns forged IDs, stale nonce/epoch, extra row, omitted row, altered digest, oversized reply | Reject before completion, fail verification where applicable, no publication or unbounded decode. |
| A07 | Replay valid result after retry or send result from another connection/job | Exactly one accepted result for current attempt. No terminal state resurrection. |
| A08 | Approve then edit input, destination, schedule zone, policy or database generation | Binding invalidated. Nothing runs under the stale approval. |
| A09 | Race revoke with approval consumption; duplicate approval/command events | Exactly one serialized winner/effect. Same command ID with different bytes rejects. |
| A10 | Pause during computation and inject a late successful reply | Waiting/paused remains. Resume starts fresh attempt over same snapshot, never publishes old reply. |
| A11 | Cancel immediately before result commit and immediately after | Before: cancelled with no result. After: completed reported honestly. No impossible mixed state. |
| A12 | Stop while queued, working, waiting, verifying, and claiming an outbox row | Persistent epoch increments, jobs cancel, no post-barrier old-epoch dispatch/result acceptance. |
| A13 | OS add initiated before Stop, callback completes after removals, then crash before stale callback | Stable identifier ultimately absent after restart reconciliation. UI admits possible earlier delivery. |
| A14 | UI Stop while database locked/full; force quit before stop transaction | In-memory dispatch stops immediately, UI says not durable. Relaunch is latched for recovery; no old jobs auto-resume. Prior OS notifications may remain and are disclosed. |
| A15 | Worker hangs and ignores cancel; disconnect doesn't prove termination | Slot stays quarantined, no replacement exceeding cap. Unconfirmed shutdown is visible. |
| A16 | Start 100+ jobs, three simultaneous restart requests, IPC reply flood | Queue bound enforced, configured live/unknown-live worker cap never exceeded, UI Stop remains responsive. |
| A17 | Kill app before/after job transaction commit and after result commit before UI update | Either whole transaction or none. No completed job without verified result, no duplicate result. |
| A18 | Kill at outbox insert/claim, before OS add, after OS add before ack, during removal | Reconciliation converges to current desired future requests using stable IDs. Elapsed uncertain requests do not replay. |
| A19 | Inject SQLite busy, full disk, I/O error, failed audit insert and migration interruption | No false success or partial authority mutation. Recovery never silently resets data. |
| A20 | Corrupt DB/index, lose transient export destination, restore an older backup | Read-only recovery for corrupt primary data, rebuild derived index only when source is valid, no automatic effects from restored approvals/outbox. Restored data uses fresh generation and disabled schedules. |
| A21 | LA spring gap/fall fold fixtures above, non-DST zone, travel and zone-rule change | Exactly one intended occurrence with stored offset, no silent device-zone shift or duplicated fold. |
| A22 | Clock jumps forward/back, reboot changes monotonic origin, sleep through deadline | Expired approvals never revive; elapsed alerts summarized without replay; attempts never use wall-clock time for timeout. |
| A23 | Denied/revoked notifications, Focus, dismissed delivered alert, closed app >30 days | Honest permission/horizon/unknown-delivery status. No delivery guarantee, no burst on reopen. |
| A24 | Stale notification click after delete/Stop, repeated click | Opens safe local UI at most, cannot approve/run/re-enable anything. |
| A25 | Signed worker probes host DB, unrelated files, secrets, network, other IPC, process creation | Document actual OS denials and residual permissions. App protocol rejects all unsupported tools. Any host data leakage blocks hostile-worker security claim/release. |
| A26 | Kill worker repeatedly and have launchd restart it | At most three explicit attempts per job, peer identity and fresh nonce checked after reconnect, no authority inherited from old attempt. |
| A27 | Export selected records, change target between approval and write, crash around rename | Only approved bytes/path/overwrite state, correct digest, no automatic ambiguous re-export. |
| A28 | Delete selected prompt referenced by jobs, FTS, previews and notification | Approved cascade removes all linked content copies, cancels affected jobs, removes desired alerts, preserves unrelated data. |
| A29 | Crash at every delete-all phase, fail Keychain/notification/cache cleanup | Relaunch resumes idempotent minimal-manifest cleanup, never resurrects records, reports incomplete categories. |
| A30 | Inspect application logs, audit, notification payload, export and local caches | No prompt/context/key leakage except explicit selected export and private intended storage. Retention bounds enforced. |
| A31 | Attempt enabling ElevenLabs without key or by imported preference/approval | Remains unavailable, zero network/usage charge, core workflows fully usable offline. |
| A32 | Decode unknown tag/version, duplicate keys, integer overflow, oversized arrays | Fail closed with bounded resource use, no fallback to generic invocation. |
| A33 | Delete-all confirmation races with Stop, then crash before/after minimal manifest fsync | Approval consumption and Stop/erase intent are atomic. Database remains until durable manifest exists. No revoked approval is used and cleanup resumes safely. |
| A34 | Stop/revoke between export preparation and publication, or during atomic publication | No new publication after Stop barrier. Already initiated publication is reported honestly, not silently retried or labelled undone. |

Additionally model-check or exhaustively enumerate small state-machine traces with a fake store/effect adapter. Invariants: no result without verification, no consumed approval without exactly one logical effect record, no worker-originated command, no accepted old-epoch reply, no more than configured live-or-unconfirmed worker slots, and all desired alert adds trace to an approved active schedule revision. The OS effect gap remains an explicit exception to any claim of exactly-once visible delivery.

## 9. Release blockers and decisions requiring validation

1. **Sandbox packaging/identity:** minimum macOS version is not chosen. Validate signed XPC peer authentication, independent entitlements, actual container/keychain isolation, process-lifecycle behavior and denial matrix before claiming least privilege. No helper was built here. The coordinating review reports Xcode is absent, so a signed prototype cannot be validated in this design session.
2. **Notifications:** confirm add/replace/remove behavior and observed pending counts on supported macOS versions. Validate the documented gap between acceptance, delivery and user acknowledgement. This app is not an alarm-clock reliability guarantee.
3. **SQLite availability and recovery:** verify FTS5, PRAGMAs, shipped SQLite version/security advisories, migration behavior, and crash/fault matrix on actual target filesystems. Logical design is not proof against power-loss/hardware failures.
4. **Live speech prerequisites:** the optional ElevenLabs adapter may ship, but live use is blocked until a user supplies a credential and satisfies exact-text disclosure/consent and cost gates. Follow the canonical adapter design for fixed provider endpoint, redirect denial, credential isolation, bounded request/audio validation, cancellation uncertainty and replacement contracts. An App Sandbox network entitlement does not itself restrict a process to one domain.
5. **Privacy and App Store review:** ship an accurate privacy policy/disclosure, entitlement justification and review notes. App Sandbox is required, not a guarantee of App Review acceptance [S1, S11]. No account or remote backend should be required to demonstrate default functionality.
6. **Threat boundary:** encryption does not hide content from an authorized unlocked host, and process revocation cannot undo past disclosure. Validate the canonical encrypted-body/search design and hostile-worker guarantees before making security claims.

No implementation, install, application code, global configuration change, runtime model, or extra agent is required to adopt this proposal. The next step is human review of these boundaries and then an explicitly authorized implementation effort.

## 10. Official sources and assertion scope

Retrieved 2026-09-17. Apple archive pages are explanatory references, not substitutes for testing current SDK/OS behavior. Current Apple documentation was also consulted through its documentation JSON representation where the HTML page required rendering.

* **[S1] Apple, App Sandbox:** <https://developer.apple.com/documentation/security/app-sandbox>. Explicit Mac App Store requirement and entitlement-based resource restrictions. JSON source: <https://developer.apple.com/tutorials/data/documentation/security/app-sandbox.json>.
* **[S2] Apple, Creating XPC Services:** <https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html>. Privilege separation versus ordinary child processes, XPC lifecycle and minimal state, message interfaces. Archived guidance requires verification for chosen deployment target.
* **[S3] SQLite, Atomic Commit:** <https://www.sqlite.org/atomiccommit.html>. Atomic rollback transactions, recovery and filesystem/hardware assumptions. Does not cover external side effects.
* **[S4] SQLite, Write-Ahead Logging:** <https://www.sqlite.org/wal.html>. Single-writer behavior, FULL versus NORMAL durability, sidecars/checkpoints and version advisories. WAL is an alternative here, not the selected baseline.
* **[S5] Apple, Scheduling and Handling Local Notifications:** <https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html>. OS-managed delivery, asynchronous scheduling, stable identifiers, cancellation, delivered observations and interaction handling. Does not promise exactly-once human-visible delivery.
* **[S6] Apple, Calendar.nextDate(after:matching:matchingPolicy:repeatedTimePolicy:direction:):** <https://developer.apple.com/documentation/foundation/calendar/nextdate(after:matching:matchingpolicy:repeatedtimepolicy:direction:)>. Explicit gap/fold matching policy API. ARGUS's chosen policies and fixtures are product rules.
* **[S7] SQLite, FTS5:** <https://www.sqlite.org/fts5.html>. Tokenizers, MATCH grammar, ranking and compile-time availability.
* **[S8] SQLite, PRAGMA:** <https://www.sqlite.org/pragma.html>. `synchronous`, `fullfsync`, `foreign_keys`, integrity checks and `secure_delete` caveats. Settings need runtime confirmation.
* **[S9] Apple Platform Security, Volume encryption with FileVault in macOS:** <https://support.apple.com/guide/security/volume-encryption-with-filevault-sec4c6dc1b6e/web>. Device/volume encryption boundary, not per-application database encryption.
* **[S10] Apple, Keychain Services:** <https://developer.apple.com/documentation/security/keychain-services>. System storage for secrets, not a substitute for application authorization or database encryption.
* **[S12] Apple, kSecUseDataProtectionKeychain:** <https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain>. Explicit Data Protection Keychain selection on macOS, access-group attributes and avoiding synchronization. Retrieved through <https://developer.apple.com/tutorials/data/documentation/security/ksecusedataprotectionkeychain.json>.
* **[S11] Apple, App Review Guidelines:** <https://developer.apple.com/app-store/review/guidelines/>. Distribution, privacy and submission obligations. Review outcome is not predetermined.
