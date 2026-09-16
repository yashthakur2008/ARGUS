# Prompt Library Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify an offline prompt Inbox/Library with immutable versions, tags/search, literal variable/context preparation, encrypted persistence, and durable waiting queue snapshots, without executing prompts.

**Architecture:** Extend the existing root Swift package, not the roadmap's historical `Packages/` layout. Keep domain logic pure, put authenticated encryption behind a narrow store protocol, and serialize prompt persistence through the existing `ReminderStore` connection/lock using a small prompt facade. The unsigned development lane uses explicit test-target-only public keys and the shipping composition remains protected-storage-unavailable until a separately authorized signed broker-private Data Protection Keychain gate passes.

**Tech Stack:** Swift 6 package tools, macOS 14+, Swift Testing, Foundation, SwiftUI, system SQLite/CSQLite, built-in CryptoKit, and a future gated Security adapter. No new package dependency or runtime service.

**Spec:** [Canonical native design](../specs/2026-09-17-argus-native-macos-design.md), especially “Prompts and execution,” “Components and dependency direction,” and “Security and platform isolation.” [Delivery roadmap](2026-09-17-argus-delivery-roadmap.md), slice 2, supplies acceptance. [Storage research](../../research/prompt-storage-feasibility.md) is supporting evidence, not an alternate spec.

## Global Constraints

The following requirements are copied verbatim from the canonical design:

- “Scheduling, notification reconciliation, search, preferences, permissions, task state, and orchestration must work with no language model and no network.”
- “Target macOS 14 or newer, subject to compiling the chosen API set.”
- “Core types must not depend on SwiftUI, UserNotifications, Keychain, or a voice SDK.”
- “SQLite writes are serialized through the authoritative service, not directly performed by views or workers.”
- “Use literal {{name}} placeholders with no nested expansion or expression engine.”
- “Limits: ten context items, 1 MiB total encoded input, 2 MiB resolved output, fifty search results per page, and a thirty-second execution budget per attempt.”
- “Use the macOS Data Protection Keychain with kSecUseDataProtectionKeychain=true, non-synchronizable items, and the broker's explicit private access group for secrets and encryption keys.”
- “Worker identities receive no access to that group.”
- “Encrypt prompt bodies, context snapshots, resolved artifacts, and retained variable values using CryptoKit authenticated encryption with a broker-only Keychain-held key.”
- “Never index encrypted bodies in plaintext.”
- “Deleting user records requires explicit confirmation.”

This planning session authorizes documentation only. It does not authorize implementation, installs, networking, live Keychain access, bundles, launches, accounts, signing changes, or pushing. All commands in the tasks below are **future implementation instructions**, not claims of execution. Future runtime defaults remain deterministic and offline. Cryptographic nonces are deliberately random, not deterministic domain outputs.

---

## 1. Observed baseline and scope choices

Reviewed baseline: `0e85b34`, branch `feat/reminders-slice`. At review start the only untracked file was the supplied storage research.

- `Package.swift`: `ArgusCore`, `ArgusStore` (Core + CSQLite), `ArgusPlatform` (Core + Store), `ArgusPresentation` (Core + Store + Platform), `ArgusApp`, and four Swift Testing targets. No external packages.
- `Sources/ArgusStore/ReminderStore.swift`: one `NSLock`, one connection, `BEGIN IMMEDIATE` writes, revision conflict checks, generation tracking. `SQLiteDatabase.swift` does not expose pointers publicly. Preserve this ownership.
- `SQLiteSchema.swift`: schema versions 0/1/2, reminder/policy/notice payload preflight, WAL + synchronous FULL, transactional migrations. There is no prompt table or key lifecycle today.
- `SQLiteRecords.swift`: strict reminder identity/revision decoding. Prompt decoding must be similarly strict and must not log malformed payloads.
- `AppModel.swift` owns reminder presentation and notification reconciliation. Do not grow it into a prompt/security controller. `TodayView.swift` owns the existing sidebar. Add a Prompts destination there with a separate model.
- `ArgusApp.swift`: bundled-app check, `ARGUS_DATA_DIR` path override, existing reminder composition. That path override must never select a test key or enable a fixture mode.
- `scripts/verify.sh` invokes `scripts/build-dev-app.sh` and performs bundling/ad-hoc signing. **Do not use either for the unsigned no-bundle validation lane.** Existing reminder evidence is historical, not evidence for this slice.

### Chosen minimal architecture, compared with alternatives

1. **Choose:** `PromptStore` facade over the same `ReminderStore` owner and lock, independent prompt generation, new schema-v3 tables, injected `ProtectedContentCodec`. This gives transactional queue/version saves without a second writer or broad rename. The platform implements the codec and can depend on Store without introducing a dependency cycle.
2. Reject a second prompt database for this first slice: it isolates migrations but adds cross-store erase/recovery coordination and another serialization authority.
3. Reject immediate generalized broker/worker infrastructure: it increases scope before signed process isolation exists. No worker, XPC, orchestrator, leases, attempts, approvals engine, shell, model, TTS, network, or automatic dispatch is implemented here.

A shared file means genuine SQLite-level structural damage can still make reminders unavailable. Key unavailability or an authentication failure in a prompt must **not** make an otherwise healthy reminder store unavailable. Keep key lookup/decryption out of startup schema validation and reminder reads.

### Delivery and availability lanes

| Lane | Work allowed by a later implementation request | Observable deliverable | Not established |
| --- | --- | --- | --- |
| A: domain | Tasks 1–2, pure unit tests | Exact records, state transitions, literal preparation | Persistence or production security |
| B: protected fixture integration | Tasks 3–7, real CryptoKit + temporary SQLite + explicit test-only provider | End-to-end service behavior, restart/corruption evidence | Live Keychain authorization or shipping feature availability |
| C: presentation with fail-closed shipping composition | Tasks 8–9, fixture-driven model tests, compile only | UI code and honest unavailable state, reminder regressions remain green | A personal-data development mode or a signed UI demonstration |
| D: production activation | Task 10, only after explicit separate authorization and signed gate | Verified broker-private key persistence and genuine app journeys | App Store acceptance, worker execution, or a full MVP |

Tasks 1–9 can be built without signing, but **must not advertise usable production protected prompt storage**. Tests may persist synthetic public content only in isolated temporary directories. An ad-hoc personal-data mode, fixture-key debug switch, legacy Keychain fallback, or automatically generated local-file key is never an intermediate deliverable.

## 2. Domain and storage contracts to freeze first

The details below resolve choices left open by the spec. They are proposed slice contracts, not claims that the canonical spec already fixes them.

### Records and lifecycle

- `Prompt`: UUID `id`, `createdAt`, `modifiedAt`, positive `revision`, `isArchived`, nullable `latestVersion: Int64`, nullable draft reference. Visible title/tags/project/favorite come from the selected draft or saved version. A saved prompt may have an editing draft without leaving Library. An initial capture with no saved version appears only in Inbox. Archive hides it from default Inbox/Library but preserves its prior membership for Restore.
- `PromptMetadata`: nonempty trimmed title, tags, optional trimmed project, favorite. Keep original display spelling. Deduplicate tags using the search normalization below and stable normalized ordering. Proposed defensive limits: title/project/tag UTF-8 lengths 512/512/128 bytes, at most 32 tags, at most 128 declared variables with names at most 64 ASCII bytes. Reject excess without truncation. Variable schema must never contain plaintext default values.
- `PromptDraft`: prompt ID, positive draft revision, nullable base saved version, metadata, body, declared variable schema, ordered context snapshots, intended workflow. Mutable only by expected-revision compare-and-swap. Persist body/context in encrypted payload, never an unencrypted Codable aggregate.
- `PromptVersion`: `(promptID, number)` immutable identity, saved time, metadata snapshot, schema, optional workflow identifier/version, body and context in trusted memory. The persistence representation uses an authenticated protected payload rather than encoding this domain object directly. Saved versions start at 1 and increase by one. All edits, including metadata changes, require a new draft and explicit Save to append a version. No update-in-place to historical rows. Captures may be incomplete but remain within byte limits. Save validates syntax/schema and moves the initial capture to Library. Missing **runtime values** do not prevent saving a reusable variable template.
- `PromptVariable`: `name`, `required: Bool`. ASCII grammar `[A-Za-z_][A-Za-z0-9_]*`, case-sensitive. `context` is reserved and cannot be declared/provided as an ordinary variable. Empty values count as missing for required fields. Optional unprovided values resolve to empty. Reject undeclared supplied keys and undeclared valid placeholders.
- `PromptContextItem`: UUID, user-visible label, UTF-8 text. User pastes/selects text and explicitly adds/reorders it in this slice. No automatic filesystem reads, URL fetch, bookmarks, or persistent file access. Encrypt labels with content conservatively because labels may contain sensitive filenames. UI calls these “selected text context,” not a full file-import feature.
- `PreparedPrompt`: saved version reference, ordered context, retained values, exact resolved UTF-8 output, workflow identity, preparation time, schema version, optional input digest (`nil` from pure Core preparation, exactly 32 bytes after service finalization). It is an in-memory value until encrypted as a queue snapshot. Only saved, unarchived versions may be newly queued. Editing/re-archiving the source after enqueue does not mutate existing snapshots.
- `PromptQueueEntry`: UUID, version reference, enqueue time, optional eligibility time, `state = waiting`, reason `runtimeUnavailable` for the allowlisted `prepare-prompt` version 1 identity or `unsupportedWorkflow` otherwise, immutable encrypted snapshot. There are **no attempts and no working/completed states created by this slice**. Show multiple entries separately, not one misleading prompt status. Queue state is a projection separate from Inbox/Library/archive state.

`PromptError: Error, Equatable, Sendable` cases: `invalidMetadata`, `invalidTemplate`, `invalidSchema`, `missingVariable(String)`, `unexpectedVariable(String)`, `contextPlaceholderRequired`, `inputTooLarge`, `outputTooLarge`, `tooManyContextItems`, `invalidUTF8`, `conflict`, `notFound`, `archived`, `draftOnly`, `protectedStorageUnavailable`, `recoveryRequired`, `corruptProtectedContent`, `unsupportedEnvelope`, `searchScopeTooLarge`, `staleSearch`, `invalidSearchPage`. Error descriptions must not interpolate body, context, values, key material, or resolved output. Schema/persistence structural failures continue to use redacted `StoreError`.

### Literal preparation and byte accounting

`PromptVariables.validateTemplate(body:schema:context:) throws` validates placeholder syntax/declarations without requiring runtime values. `PromptVariables.resolve(body:schema:values:context:) throws -> String` performs one left-to-right scan of the original template. Replace literal tokens once, never scan replacement values again. Reject nested/unclosed braces and expression-like token names as invalid templates, never evaluate them. Shell/HTML/SQL-looking text outside tokens is ordinary text.

`{{context}}` expands to selected UTF-8 item texts joined by exactly `\n\n` in displayed order. Empty selection resolves to empty text. A nonempty selection without the placeholder returns `contextPlaceholderRequired`, requiring an explicit template edit. Repeated context placeholders each expand and count toward the output bound.

Freeze `PromptInputEncoding.v1`: UTF-8 fields prefixed with unsigned 64-bit big-endian byte lengths, counts encoded as unsigned 64-bit big-endian, fixed field order, sorted variable keys by ASCII byte order, context in display order, explicit optional-field presence bytes. Include template, variable schema/names/values, context labels/text, workflow identity, and source version reference. The full encoded input including framing must be <= 1,048,576 bytes. Validate increments with overflow-safe arithmetic before allocation. Resolved UTF-8 output must be <= 2,097,152 bytes. Count bytes, not graphemes. No truncation. Crypto envelope overhead is bounded separately and is not counted as user input. Incomplete draft encoding uses the same limit with no supplied runtime values. Use rejection tests at exact encoded limits, not character approximations.

Preparation/preview is deterministic domain computation, **not a worker run**. Future attempt execution must retain the canonical 30-second budget but no timer or execution loop is introduced here. A changed preparation requires a fresh preview and new queue snapshot. No approval is issued or consumed. Future approvals must bind the digest and be invalidated on input changes.

### Search contract

`PromptSearchNormalization.v1`: precomposed canonical Unicode normalization, Foundation case-insensitive folding using fixed `en_US_POSIX`, then precomposition again. No diacritic/width folding, locale-dependent user settings, regex, SQL LIKE wildcards, or query language. Pin golden vectors for composed/decomposed accents, ASCII, Turkish I, and case-fold expansions. If a supported OS changes vectors, reject that implementation/version change until reviewed, not silently relabel the same normalization version.

Default scope: latest saved version of each nonarchived Library prompt, not Inbox drafts or all historical versions. UI may explicitly choose Inbox or archived scope, with one draft/latest record per prompt. Search title/body by literal normalized substring, exact normalized tag/project filters combined by AND (all selected tags required). Empty query matches all records within the explicit metadata filters. Project nil differs from a named project.

Capture prompt generation + exact IDs/version or draft revisions + normalization version + query/filter values as `PromptSearchSnapshot`. Proposed first-slice bound: at most 1,024 metadata-filtered candidates. If exceeded, return `searchScopeTooLarge` and ask the user to narrow tags/project/scope. Never silently take the first 1,024 or give a partial count. Process/decrypt one candidate at a time, bounded by its input limit, retain only IDs/metadata match projections, and erase references when the query ends. Recheck generation before publishing. Missing key or corrupt candidate fails the whole requested body-search scope with a visible error, not a skipped row or a metadata-only result masquerading as a complete body search.

Sort all matches by normalized title's UTF-8 lexical bytes then canonical UUID string, page at 50, retain exact total. Revalidate page IDs, uniqueness, membership and ordering against the captured snapshot. Source changes invalidate the page token with `staleSearch`, requiring explicit Refresh. No plaintext body index, FTS table, snippets cache, SQLite temporary text table, persisted query text, or background indexing. A separately labeled metadata-only listing may remain available when keys are unavailable, without claiming body search succeeded.

### Encryption and serialized persistence

`ProtectedContentCodec` lives in ArgusStore and takes only bounded `Data` and typed identities. `CryptoKitPromptCodec` lives in ArgusPlatform and depends on a narrow `PromptKeyProvider`. Only the broker's composition root owns the production provider. Core uses Foundation values only. Cross-target contracts and their initializers must be explicitly `public`; snippets below show interface shape, not complete implementation bodies.

```swift
// Proposed public Store boundary, no CryptoKit/Security types escape it.
struct ProtectedContentIdentity: Equatable, Sendable {
  let storeID: UUID
  let recordID: UUID
  let revision: Int64       // saved version, draft revision, or queue snapshot version
  let field: ProtectedField // draft, version, queueSnapshot
  let metadata: Data       // canonical nonsecret row metadata authenticated as AAD
}
enum ProtectedField: String, Sendable { case draft, version, queueSnapshot }
protocol PromptInputDigesting: Sendable {
  func digest(_ canonicalInput: Data) throws -> Data // exactly 32 SHA-256 bytes
}
protocol ProtectedContentCodec: Sendable {
  func seal(_ plaintext: Data, identity: ProtectedContentIdentity) throws -> Data
  func open(_ envelope: Data, identity: ProtectedContentIdentity) throws -> Data
}
```

Envelope v1: magic `ARGUSP01`, envelope version, fixed algorithm ID for AES-256-GCM, key identifier of 1–64 ASCII bytes, 12-byte nonce, ciphertext length, ciphertext, 16-byte tag. Reject unknown versions/algorithms, truncation, trailing bytes, impossible lengths, or invalid UTF-8 after authentication. Use canonical length-prefixed AAD binding header/key ID + store ID + record ID + revision + field + canonical metadata. Authenticate metadata/schema/workflow snapshots as well as protected bytes so a changed variable declaration or workflow cannot redirect preparation. Queue AAD includes source reference, entry ID, eligibility time and waiting reason. Mutable root archive state/revision is checked transactionally rather than included in immutable version AAD. CryptoKit `AES.GCM.seal` chooses fresh random nonce (`nonce: nil`). Never persist a key or generate a deterministic production nonce. Fixture keys live only in test source. Exact public known-answer vectors may supply nonce only through a test-only vector test, not a shipping default.

Maximum protected draft/version plaintext equals the bounded canonical input representation (1 MiB). Queue encoding contains source/input plus resolved output and fixed metadata, so set its independent encoded bound to 4 MiB, validating input/output limits individually first. Envelope bound is plaintext cap + 256 bytes. Reject before copying/decrypting an oversized blob. Keep digest inside the encrypted queue payload to avoid an unnecessary plaintext low-entropy-content verifier. Real ciphertext and nonce are intentionally nondeterministic while preparation/digest inputs are canonical.

Schema v3 adds:

| Table | Plaintext columns / constraints | Protected bytes |
| --- | --- | --- |
| `prompt_store_metadata` | singleton ID, immutable store UUID, prompt generation >= 0, lifecycle `uninitialized/ready`, bounded key ID nullable only while uninitialized | None |
| `prompts` | UUID PK, revision > 0, dates, archive flag, nullable latest saved version | None |
| `prompt_drafts` | prompt ID PK/FK, revision > 0, nullable base version, validated metadata/schema/workflow | One authenticated draft envelope including body/context |
| `prompt_versions` | composite PK(prompt ID, version > 0), FK prompt, saved date, metadata/schema/workflow snapshot | One authenticated version envelope including body/context |
| `prompt_queue` | UUID PK, source composite FK, enqueue/eligibility dates, state constrained to waiting, reason | One authenticated snapshot containing retained values/context/resolved output/digest |

For bounded envelope reads, inspect SQLite BLOB byte count before copying into Data, not after the existing unbounded `blob` helper returns. Metadata JSON must be a dedicated type with no body/value/context properties. Schema names and labels may disclose user intent, so disclose that metadata (including project, variable names, workflow, dates and counts) is not encrypted. Values and context labels stay protected. Add CHECK/foreign-key constraints, validate identities and references on decoding, forbid arbitrary table-name input. Compare decoded protected identity to expected row identity after open. Authenticated encryption prevents substitution/tampering, not wholesale restoration of an older valid database. Monotonic revisions detect ordinary stale writes, not adversarial filesystem rollback; do not promise rollback resistance.

`PromptStore(owner: ReminderStore, codec: any ProtectedContentCodec, digester: any PromptInputDigesting, clock: @Sendable () -> Date)` keeps the owner strongly and uses **only its existing lock/connection**. No independent lock or raw connection escapes. It exposes capture, updateDraft, saveVersion, beginEdit, archive/restore, snapshot, history, prepare, enqueue, search, and queue snapshot reads. Each write increments prompt generation only, avoiding spurious reminder-notification changes. It does not call public owner methods while holding the same nonrecursive lock.

Seal outside the SQLite transaction, then enter the owner lock, compare expected revisions/generation and commit metadata + encrypted blob + reference updates atomically. No SQLite binding, error string, audit event, WAL, journal, or temporary table receives protected plaintext. For reads, copy bounded envelopes/metadata under the lock, decrypt outside, then recheck prompt generation under the lock before returning a current snapshot. Do not hold the lock across a key interaction or an `await`. A stale seal result can be discarded safely, not retried against a different revision without revalidation.

Migration from v2 creates empty tables without looking up/creating a key. Preserve the existing reminder generation and bytes of reminder payloads. Existing healthy reminders work with an uninitialized or unavailable prompt key. New prompt metadata reads show a real unavailable/recovery state, not an empty-library success. Payload authentication is done on protected operations, not a global reminder startup gate.

## 3. File ownership and integration scopes

All paths below are proposed unless explicitly called existing. No new top-level package is needed.

| Scope | Create | Existing files to modify | Owner constraint |
| --- | --- | --- | --- |
| Domain | `Sources/ArgusCore/Prompt.swift`, `PromptVersion.swift`, `PromptVariables.swift`, `PromptInputEncoding.swift`, `PromptSearch.swift`, `PromptPreparation.swift` | None | No adapter imports |
| Store | `Sources/ArgusStore/ProtectedContentCodec.swift`, `PromptStore.swift`, `PromptSQLiteSchema.swift`, `PromptSQLiteRecords.swift`, `PromptSearchStore.swift`, `PromptQueueStore.swift` | `SQLiteSchema.swift`, bounded BLOB binding in `SQLiteDatabase.swift` | Single store owner/lock, preserve reminder API |
| Encryption | `Sources/ArgusPlatform/PromptKeyProvider.swift`, `CryptoKitPromptCodec.swift`, `PromptEnvelope.swift`, `CryptoKitPromptInputDigester.swift`, `UnavailablePromptCodec.swift` | None | No live Security calls in unsigned lane |
| Future adapter | `Sources/ArgusPlatform/DataProtectionPromptKeyProvider.swift`, `PromptKeyInitialization.swift` | App composition only after gate | Fixed broker namespace/group, signed authorization required |
| Presentation | `Sources/ArgusPresentation/PromptLibraryModel.swift`, `PromptEditorDraft.swift`, `PromptLibraryView.swift`, `PromptEditor.swift`, `PromptVersionHistoryView.swift`, `ResolvedPromptView.swift` | `TodayView.swift`, `Sources/ArgusApp/ArgusApp.swift` | Separate model, unavailable state defaults |
| Evidence | `docs/verification/2026-09-17-prompt-library-slice.md` | `README.md` only to report actual state | Separate fixture/signed/manual evidence |

Tests use matching files specified per task. Test-only fixture providers are duplicated minimally within the consuming test targets or included by explicit test-only source configuration, never put in `Sources/`. If CryptoKit is directly imported by a test, it is a system framework, not an external package. Store integration tests can use `ArgusPlatform` by adding that dependency to `ArgusStoreTests` only in `Package.swift`; Platform already depends on Store, but this test-target edge creates no production cycle. Do not alter the shipping target dependency graph to share fixture support.

## 4. Test-first tasks

Each numbered task is a reviewable commit, not permission to begin implementation now. Within each task perform the red/green steps in order. Record command, failing assertion/compiler diagnostic, green result, and evidence class. A missing symbol is an initial red only; follow with behavioral assertions that can fail for wrong implementations. Run the full package tests before each task commit.

### Test command setup for future work

Use an **already present** working toolchain only. The previous reminder record identifies this candidate, whose current availability must be checked without downloading/installing:

```sh
export ARGUS_SWIFT=/Users/yashthakur/.jcode/scratch/argus-swift-6.1.2/expanded/swift-6.1.2-RELEASE-osx-package.pkg/Payload/usr/bin/swift
test -x "$ARGUS_SWIFT" || exit 1
"$ARGUS_SWIFT" --version
# T denotes this command in each task below, with a concrete --filter appended:
"$ARGUS_SWIFT" test --disable-xctest --enable-swift-testing --skip-update
```

If unavailable/broken, record a toolchain blocker. Do not repair or install implicitly. There are no package dependencies to fetch. Do not run `scripts/verify.sh`, `scripts/build-dev-app.sh`, `open`, signing commands or application binaries in lanes A–C. `swift test` invokes test executables, not the application. Native UI journeys, OS restarts and signed tests are separately gated.

### Task 1: Records, immutable version rules and Inbox lifecycle

**Files:** Create `Sources/ArgusCore/Prompt.swift`, `PromptVersion.swift` and the normalization primitive in `PromptSearch.swift` (needed now for metadata tag deduplication). Create `Tests/ArgusCoreTests/PromptVersionTests.swift`.

**Interfaces:** `Prompt.capture(id:metadata:body:schema:context:workflow:now:) throws -> PromptDraft`; `PromptVersion.save(draft:number:now:) throws -> PromptVersion`; `PromptVersion.editDraft(revision:now:) -> PromptDraft`. Dates and IDs are supplied explicitly. `PromptMetadata(title:tags:project:isFavorite:) throws`, `PromptVariable(name:required:) throws`. These domain values do not persist anything.

- [ ] Write the red version/metadata tests with fixed date `Date(timeIntervalSince1970: 1_800_000_000)` and UUIDs ending 0001/0002. Representative test (constructors above supply all fields):

```swift
@Test func promptVersionCopyDoesNotMutateHistory() throws {
  let meta = try PromptMetadata(title: "Release", tags: ["Work", "work"], project: "ARGUS", isFavorite: true)
  let draft = try Prompt.capture(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    metadata: meta, body: "Review {{project}}", schema: [try PromptVariable(name: "project", required: true)],
    context: [], workflow: nil, now: Date(timeIntervalSince1970: 1_800_000_000))
  let v1 = try PromptVersion.save(draft: draft, number: 1, now: draft.modifiedAt)
  var editing = v1.editDraft(revision: 1, now: draft.modifiedAt)
  editing.body = "Second {{project}}"
  #expect(v1.body == "Review {{project}}")
  #expect(editing.baseVersion == 1)
  #expect(v1.metadata.tags.count == 1)
}
```

- [ ] Run T with `--filter PromptVersion`; expect missing types, then behavioral failures. Add cases for empty title, duplicate normalized tags, metadata byte limits, invalid timestamps/revisions, invalid decoded values, archived initial capture restoring to Inbox, saved record restoring to Library, and saved record with a separate editing draft.
- [ ] Implement value records and explicit validation. Keep mutable editor fields separate from immutable `let` version fields. Decode through validation, not synthesis that bypasses invariants.
- [ ] Rerun filtered and full T. Verify `PromptVersion` can be round-tripped without permitting invalid identities or revisions. No encryption claim in this task.
- [ ] Commit only domain/test paths: `feat: define prompt records and immutable version lifecycle`.

### Task 2: Literal variables, context order and bounded preparation

**Files:** Create `PromptVariables.swift`, `PromptInputEncoding.swift`, `PromptPreparation.swift`; create `Tests/ArgusCoreTests/PromptVariablesTests.swift`, `PromptPreparationTests.swift`.

**Interfaces:** validation/resolve functions defined in §2; `PromptPreparation.prepare(version: PromptVersion, values: [String: String], context: [PromptContextItem], now: Date) throws -> PreparedPrompt`. `PromptContextItem(id:label:text:) throws` takes UTF-8 String, with a separate `init(id:label:utf8: Data) throws` that rejects invalid encoding. Digest bytes are added by the service using its injected `PromptInputDigesting` dependency when finalizing the canonical prepared input, not by importing CryptoKit into Core.

- [ ] Write literal substitution tests first:

```swift
@Test func promptVariablesNeverExpandReplacementText() throws {
  let result = try PromptVariables.resolve(body: "A={{name}} B={{context}}",
    schema: [try PromptVariable(name: "name", required: true)],
    values: ["name": "{{context}}; $(touch forbidden)"], context: [])
  #expect(result == "A={{context}}; $(touch forbidden) B=")
}
@Test func promptVariablesRequireExplicitContextPlaceholder() throws {
  let item = try PromptContextItem(id: UUID(), label: "Selected", text: "public fixture")
  #expect(throws: PromptError.contextPlaceholderRequired) {
    try PromptVariables.resolve(body: "plain", schema: [], values: [:], context: [item])
  }
}
```

- [ ] Run T `--filter PromptVariables`; expect red. Add schema-only Save acceptance with no values, missing/empty required value failure at Prepare, optional omitted value, duplicate/invalid names, reserved context rejection, nested/unclosed tokens, unknown supplied key, repeated placeholders, Unicode data, and invalid UTF-8. Use `context = ["one", "two"]`, expect `one\n\ntwo`, then reverse order and expect changed preview.
- [ ] Implement a single-pass tokenizer and overflow-safe v1 length-prefixed encoder. Add exact encoded 1 MiB input and 2 MiB output acceptance, +1-byte rejection, 10/11 context cases, multibyte boundary cases, and repeated-value expansion crossing output limit. Expected failure leaves no partial output. Test canonical encoding independence from dictionary insertion order.
- [ ] Run T `--filter PromptPreparation`, filtered variables, then full T. Assert different context order/value/source version changes canonical input bytes and identical inputs do not change them.
- [ ] Commit only domain/tests: `feat: prepare literal bounded prompt snapshots`.

### Task 3: Real authenticated envelope with explicit test-only keys

**Files:** Create Store `ProtectedContentCodec.swift`; Platform `PromptKeyProvider.swift`, `PromptEnvelope.swift`, `CryptoKitPromptCodec.swift`, `CryptoKitPromptInputDigester.swift`, `UnavailablePromptCodec.swift`; create `Tests/ArgusPlatformTests/PromptEncryptionTests.swift`, `PromptKeyBoundaryTests.swift`, `PromptFixtureKeyProvider.swift` (test only).

**Interfaces:** Store codec and digester contracts in §2. `CryptoKitPromptInputDigester.digest(_:)` returns SHA-256 bytes and is tested against SHA-256 of empty input, hex `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`. Platform `PromptKeyProvider.key(id: String) throws -> Data` returns exactly 32 bytes; no default provider parameter. `CryptoKitPromptCodec(provider:any PromptKeyProvider,keyID:String)`. Provider errors map to typed unavailable/recovery states, not empty key data. `UnavailablePromptCodec()` always throws `protectedStorageUnavailable` and never generates a key. The key provider protocol has no arbitrary service/account/group parameters and no create method in this lane.

- [ ] Write real CryptoKit tests using `Data(0..<32)` as an explicitly public synthetic key, never user content. Test provider exists only under `Tests/`. Core assertion:

```swift
@Test func promptEncryptionAuthenticatesRecordIdentity() throws {
  let codec = CryptoKitPromptCodec(provider: PromptFixtureKeyProvider(bytes: Data(0..<32)), keyID: "fixture-v1")
  let identity = ProtectedContentIdentity(storeID: UUID(), recordID: UUID(), revision: 1, field: .version, metadata: Data("fixture-metadata-v1".utf8))
  let bytes = Data("PUBLIC-PROMPT-SENTINEL".utf8)
  let sealed = try codec.seal(bytes, identity: identity)
  #expect(try codec.open(sealed, identity: identity) == bytes)
  let wrong = ProtectedContentIdentity(storeID: identity.storeID, recordID: identity.recordID, revision: 2, field: .version, metadata: Data("fixture-metadata-v1".utf8))
  #expect(throws: (any Error).self) { try codec.open(sealed, identity: wrong) }
}
```

- [ ] Run T `--filter PromptEncryption`; expect red. Add tamper matrices for each header/nonce/tag/ciphertext/AAD field, different store/record/field/key ID/key, short/oversized/trailing envelope, unknown versions and malformed key length. Assert no plaintext return. Embed the standard zero-length AES-256-GCM vector (NIST GCM validation format): 32 zero key bytes, 12 zero nonce bytes, empty plaintext/AAD, empty ciphertext, tag hex `530f8afbc74536b9a963b4f1c4cb738b`. Verify it directly through CryptoKit in the test target using the fixed nonce, then verify envelope framing separately. No network retrieval and no fixed-nonce injection in the shipping codec.
- [ ] Implement AES-GCM with authenticated header and canonical AAD. Enforce caps before allocation, `nonce:nil` for all production seal calls, authenticate before UTF-8/domain decoding. No content-bearing error descriptions. Decrypted key/plaintext lifetimes are bounded by the operation; do not promise perfect Swift memory zeroization.
- [ ] Run T `--filter PromptKeyBoundary`: fake providers throw absent/entitlement/interaction/cancel/unknown failures. Every protected operation throws, no fallback invocation, no retry that widens authority. Then full T. Scan `Sources/` for fixture names/bytes and default-provider/environment-selection paths.
- [ ] Commit only codec/platform/tests: `feat: add fail-closed authenticated prompt envelopes`.

### Task 4: Transactional schema v3 without a Keychain dependency

**Files:** Create `PromptSQLiteSchema.swift`, `PromptSQLiteRecords.swift`; modify existing `SQLiteSchema.swift` and `SQLiteDatabase.swift` only for v3 routing and checked BLOB lengths; create `Tests/ArgusStoreTests/PromptMigrationTests.swift`. Update version expectations in `StoreMigrationTests.swift` intentionally, preserving all old assertions about payloads/generation.

**Interfaces:** internal `SQLiteDatabase.preparePromptSchema()` and `validatePromptSchema()` called by the existing schema transaction. Connection remains owned by `ReminderStore`. No codec/key access in schema helpers.

- [ ] Add a healthy v2 fixture containing reminder, notification policy and notice. Assert open upgrades to v3, all old data and generation unchanged, prompt metadata uninitialized, all prompt content tables empty, and zero key-provider calls. Add a v1 fixture upgrading through both migrations. Add future-schema rejection and malformed v3 columns/FKs/checks.
- [ ] Run T `--filter PromptMigration`; expect schema version/table assertions to fail. Extend `StoreMigrationTests` only after new tests establish the desired new floor.
- [ ] Implement the §2 schema in the existing transaction. Preflight known schema before journal/header mutation as the existing implementation does. Never run a plaintext “backfill,” since no prompt storage exists. Keep protected payload authentication out of startup validation.
- [ ] Inject table/index name collision midway through migration, compare `user_version`, reminder generation, payload bytes, and table list after failure and reopen twice. No partial tables or changed v2 marker. Test old corrupt reminder input still fails before migration. Test BLOB lengths before `Int32` conversion and decoding copies. Run filtered and full T.
- [ ] Commit store/migration tests only: `feat: migrate prompt storage without touching protected keys`.

### Task 5: Encrypted Inbox, immutable saves, history and archive/restore

**Files:** Create `PromptStore.swift`; extend `PromptSQLiteRecords.swift`; create `Tests/ArgusStoreTests/PromptPersistenceTests.swift`, `PromptCorruptionTests.swift`, `PromptStoreFixture.swift`. Modify `Package.swift` only to add `ArgusPlatform` to the Store test target for real-codec fixtures.

**Interfaces:** `PromptStore` initializer in §2. `capture(_ draft: PromptDraft) throws`; `updateDraft(_ draft: PromptDraft, expectedRevision:Int64) throws`; `saveVersion(promptID:UUID, expectedPromptRevision:Int64, expectedDraftRevision:Int64) throws -> PromptVersion`; `beginEdit(promptID:UUID, expectedRevision:Int64) throws -> PromptDraft`; `setArchived(promptID:UUID, archived:Bool, expectedRevision:Int64) throws`; `snapshot() throws -> PromptLibrarySnapshot`; `history(promptID:UUID, beforeVersion:Int64?, limit:Int) throws -> [PromptVersion]` (1–50 versions per request, newest first, reject excess limits rather than loading unbounded history). `PromptLibrarySnapshot` contains generation and paginated metadata-only Inbox/Library/archived records plus availability (50 rows per section/page with exact metadata counts), never a fabricated successful empty result on failure.

- [ ] Write the capture → Inbox → validated Save → Library → beginEdit → Save twice → three immutable versions test using real SQLite and the real codec. Reopen with the same explicit test provider and injected `CryptoKitPromptInputDigester()` and verify all dates/IDs/content/metadata/version references exactly. A reused earlier `PromptVersion` still equals its original value. Archive and restore both an initial capture and a saved prompt, reopen twice, verify preserved membership and history.
- [ ] Run T `--filter PromptPersistence`; expect red. Add two concurrent writers with the same expected revisions: exactly one succeeds, loser reports conflict, no lost update or version-number gap. Reject archive/save with stale revision. A failed validation must preserve draft and Library status.
- [ ] Implement encrypt-before-bind plus compare-and-swap transactions. For a fixture store, `PromptStoreFixture.swift` initializes the empty metadata row to `ready` with `fixture-v1` using test-owned CSQLite fixture setup before constructing the service, never a production initializer flag or shipping fallback. The fixture supplies a codec whose public test key is explicit and a real digester. For uninitialized shipping store, protected writes remain unavailable until Task 10. Errors preserve existing data and unsaved editor text in memory only. No body logging or plaintext “draft autosave” to defaults/caches.
- [ ] Add transaction fault injection internal to tests at: after version INSERT, before latest pointer update, after pointer update before COMMIT. All failures roll back version, pointer, draft removal, and generation together. Close/reopen twice to verify. Store failpoints are internal closure injection through a test-visible initializer, default no-op, never runtime environment flags.
- [ ] Run T `--filter PromptCorruption`: wrong/missing key, invalid key ID, changed ciphertext, swapped record/version envelopes, malformed protected data, unsupported envelope, orphan version/reference, invalid dates. Return typed failure and preserve ciphertext, never overwrite/rekey/drop records. Show healthy metadata as unavailable, not zero records. Reminder list/save/notices still work when only the prompt codec is unavailable. Run full T.
- [ ] Commit scoped store/schema/test changes: `feat: persist encrypted prompt drafts and version history`.

### Task 6: Bounded snapshot search and exact pagination

**Files:** Extend `PromptSearch.swift` from Task 1 and create `PromptSearchStore.swift`; create `Tests/ArgusCoreTests/PromptSearchTests.swift`, `Tests/ArgusStoreTests/PromptSearchStoreTests.swift`.

**Interfaces:** `PromptSearchQuery(text:String,tags:[String],project:String?,scope:PromptSearchScope)`; scope cases `library`, `inbox`, `archived`. `PromptStore.search(_ query:PromptSearchQuery) throws -> PromptSearchSnapshot`; `PromptStore.page(snapshot:PromptSearchSnapshot,index:Int) throws -> PromptSearchPage`. Snapshot stores query, normalizationVersion=1, generation, candidate identities, ordered match IDs and total, not body text. Page exposes metadata and exact source reference, maximum 50 records. Index starts at 0 and must be nonnegative.

- [ ] Write normalizer golden vectors and literal matching tests first. Use query `.*`, `%`, `_`, `{{x}}`, and SQL-looking text as literal text, not operators. `tag=Work` must not match `Workshop`; project and two tags are AND filters. Same normalized titles tie-break by stable UUID. Draft edits do not affect default Library search until Save.
- [ ] Run T `--filter PromptSearch`; expect red. Use 121 matches with IDs 1–121, expect page counts `[50,50,21,0]`, exact total 121 on each, no duplicate IDs, frozen order. Add no-match/empty-query cases, composed/decomposed accents and locale-change fixtures. Force duplicated/missing/unmatched IDs into a page token and expect rejection.
- [ ] Implement metadata candidate capture under lock, bounded decrypt/match outside lock, generation recheck before publication. Reject 1,025 candidates rather than returning a partial result. With filters narrowing to 1,024, process all and produce exact total. No persistent search query/body cache.
- [ ] Mutate save/archive/draft after snapshot and before page retrieval, expect `staleSearch`. Corrupt the final candidate or remove its key and expect the whole search to fail, never a partial successful page. Assert no new schema/FTS/temp persistent tables and no source plaintext persists. Run filtered and full T.
- [ ] Commit search paths/tests only: `feat: search bounded encrypted prompt snapshots literally`.

### Task 7: Exact preview and immutable waiting queue, no dispatch

**Files:** Create `PromptQueueStore.swift`; extend `PromptPreparation.swift`; create `Tests/ArgusStoreTests/PromptQueueTests.swift`, `Tests/ArgusPlatformTests/PromptInputDigestTests.swift`.

**Interfaces:** `PromptStore.prepare(promptID:UUID, version:Int64, values:[String:String], context:[PromptContextItem]) throws -> PreparedPrompt`; `enqueue(_ prepared:PreparedPrompt, id:UUID, eligibleAt:Date?) throws -> PromptQueueEntry`; `queueEntries() throws -> [PromptQueueEntry]`; `queueSnapshot(id:UUID) throws -> PreparedPrompt`. The injected Store protocol `PromptInputDigesting` is implemented by Platform `CryptoKitPromptInputDigester.digest(_:)` using SHA-256 over canonical input v1, using no key bytes in the digest. Store never imports Platform. Finalize `PreparedPrompt.inputDigest` through this dependency before displaying/queueing it; reject nil or non-32-byte digests at enqueue. Digest is not an approval and is stored only inside the encrypted snapshot. At enqueue, re-read the explicit saved source and recompute/validate canonical preview/digest, rejecting inconsistent or forged prepared objects. Selecting an older saved version explicitly is allowed; the UI must keep that version visible if a newer one exists. Never silently swap to latest. Archive state is checked again at commit.

- [ ] First test: Save v1, prepare required variables/context, assert exact preview, enqueue entry A, edit/save v2, prepare/enqueue entry B, reopen twice. A still references v1 with original values/context/resolved output, B references v2, both are waiting, no attempts or execution receipts exist. Queue entry UUID is the idempotency key: identical replay returns the same record, differing payload under same ID conflicts.
- [ ] Run T `--filter PromptQueue`; expect red. Cover free-form nil/unknown workflow `unsupportedWorkflow`, supported prepare identity `runtimeUnavailable`, past/future eligibility neither dispatching nor granting permission, initial draft and archived source rejected, no context placeholder and missing values rejected before any SQL write.
- [ ] Implement source validation, platform digest, authenticated encrypted snapshot and queue row in one transaction. The service does not spawn tasks/processes or report a completed prompt. Preview changes require a new explicit Queue action, never mutate an existing queue record. Source edits after queueing cannot alter it.
- [ ] Corrupt digest/source reference/resolved bytes, inject failure after queue INSERT before COMMIT, reopen with key unavailable, and simulate duplicate concurrent enqueue. Assert no partial row, no extra entry, no plaintext return on failure. Spy/structural tests verify no workflow executor, URLSession, shell, notification submission or voice call is reachable from preparation/enqueue. Run filtered and full T.
- [ ] Commit queue/digest/tests only: `feat: retain encrypted waiting prompt queue snapshots`.

### Task 8: Separate prompt presentation and safe shipping composition

**Files:** Create the six presentation files in §3; modify `TodayView.swift`, `ArgusApp.swift`; create `Tests/ArgusPresentationTests/PromptLibraryModelTests.swift`, `PromptEditorDraftTests.swift`, `PromptCompositionTests.swift`.

**Interfaces:** `@MainActor @Observable PromptLibraryModel(store:PromptStore)` submits typed actions, tracks editor state and distinct availability/error/empty states, and exposes immutable history/queue projections. `PromptLibraryView(model:)`, `PromptEditor(model:draft:)`, `PromptVersionHistoryView(versions:)`, `ResolvedPromptView(prepared:)`. `TodayView.init(model:AppModel, prompts:PromptLibraryModel)` adds the Prompts destination without changing reminder notification behavior. Composition passes `UnavailablePromptCodec()` and `CryptoKitPromptInputDigester()` in the unsigned shipping lane, not a fixture provider. The nonsecret digest implementation does not authorize key access or protected operations.

- [ ] Write model tests before UI: capture/save/missing-variable messages, Inbox vs Library empty copy, initial/editing draft distinction, history comparison, exact preview ordering, archive/restore, separate waiting entries, stale search refresh, conflict-preserved editor input. Inject codec unavailable and assert prominent “Protected prompt storage unavailable” plus explanation, disabled capture/save/prepare/queue, no deceptive “No prompts yet.” Reminders remain usable.
- [ ] Run T `--filter PromptLibraryModel`; expect red. Test a failing/stale asynchronous refresh cannot overwrite newer state with old decrypted content. On key/session availability loss clear history/body/preview/search sensitive references, keep metadata marked unavailable, and require explicit recovery rather than displaying stale decrypted success. No automatic authentication prompts from background refresh.
- [ ] Implement native views using separate model, explicit text-context add/reorder controls, bounded variable form, history inspection, favorite/tag/project fields and exact resolved preview. Save validation explains fields without exposing values in global notices. Add keyboard access, VoiceOver labels, dynamic/system fonts, reduced-motion-safe feedback, and light/dark support. No fake Hands activity, generic approval, export, delete-all or runtime controls.
- [ ] Composition tests statically inspect shipping sources and exercise unavailable composition: no `PromptFixtureKeyProvider`, fixture bytes, environment/defaults/argument key selector, random fallback key, legacy `SecKeychain`, sync-enabled key, or forced plaintext path. `ARGUS_DATA_DIR` changes location only. Update app call sites to preserve reminder composition. Run filtered/full T and compile with `"$ARGUS_SWIFT" build --skip-update` only, no bundle/launch.
- [ ] Commit UI/model/composition/tests only: `feat: present prompt library with honest protected-storage gating`.

### Task 9: Acceptance, restart, corruption and privacy evidence

**Files:** Create `Tests/ArgusPresentationTests/PromptLibraryAcceptanceTests.swift`, `Tests/ArgusStoreTests/PromptPrivacyTests.swift`, `PromptRestartTests.swift`, and `docs/verification/2026-09-17-prompt-library-slice.md`; modify README only with actual availability/evidence.

**Interfaces:** Use actual service/model/store/codecs from Tasks 1–8, explicit fixed public keys in tests, temporary directories, recording error/log sink with redaction assertions. Do not replace production SQLite/encryption code with a mock for acceptance.

- [ ] Write an end-to-end model acceptance test with synthetic prompt `Review {{project}}\n{{context}}`, tag Work, project ARGUS, favorite true. Capture, save, edit twice, compare three versions, search, resolve `project=PUBLIC-ALPHA`, select two contexts, preview exact output, queue, drop all model/store references, reopen twice, inspect original queue snapshot. Assert counts, IDs, versions, bytes and waiting reason, not only “no throw.”
- [ ] Run T `--filter PromptLibraryAcceptance`; expect failures for any missing integration and fix only those seams. Add data-level leakage test with distinct public sentinels for body, old-version body, context label/text, variable value and resolved artifact. Inspect bound SQL parameters via a test recorder as the primary boundary proof. While WAL is present, inspect DB/WAL/journal and any app-created auxiliary files, then checkpoint/reopen and scan again. Assert all protected writes pass envelopes, no protected plaintext binding, no FTS/body cache. Error/log/audit captured output must omit all sentinels and key bytes. A byte scan alone is supplementary, not proof of forensic erasure.
- [ ] Run restart matrix below against real temporary files. Catch exceptions as transactional fault-injection evidence, not a claim of OS process-kill durability. A future controlled process-kill harness using a dedicated test executable and synthetic directory may add crash evidence without launching ARGUS, but must be separately scoped and reported distinctly.
- [ ] Run full T, `"$ARGUS_SWIFT" build --skip-update`, `git diff --check`, and shipping dependency/fixture scans. Record exact toolchain, OS, commit, commands, assertion totals, actual failures/fixes and limitations. Never copy historical reminder test totals as new results.
- [ ] Commit acceptance/tests/evidence/README only: `test: verify prompt persistence privacy and restart behavior`.

### Task 10: Signed broker-private Keychain gate, separately authorized and blocked

**Files (future authorized work only):** `DataProtectionPromptKeyProvider.swift`, `PromptKeyInitialization.swift`, `Tests/ArgusPlatformTests/PromptKeyInitializationTests.swift`, `DataProtectionPromptKeyProviderTests.swift`; signed acceptance checklist `Tests/PlatformAcceptance/PromptKeychainChecklist.md`; actual Xcode target/entitlement configuration chosen only after genuine identities/profiles are known. Do not fabricate an Xcode project, Team ID, group or signing asset in Tasks 1–9.

**Interfaces:** provider from Task 3 plus a separate broker-internal initialization service. A testable `SecurityItemClient` protocol wraps copy/add/update/delete with recorded query dictionaries, while the signed production implementation calls SecItem. No worker API returns a key or accepts arbitrary Keychain names. Test fakes implement the client without invoking Security.

- [ ] Before any live operation, obtain explicit authorization for the synthetic signed gate and confirm actual bundle/application/private-group identifiers, user login context, authorized development profile and code identity, distribution channel restrictions, and selected accessibility policy. Candidate `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is **not approved merely by this plan**. Decide foreground/background behavior, lock/session invalidation and recovery disclosure first. Missing prerequisites leave this task blocked, not skipped as success.
- [ ] Write fake-client query tests first: every operation includes Data Protection selector and exact broker private group, fixed service/account/key-version namespace, non-synchronizable item creation, no group omission/retry, malformed returned attributes/bytes rejected. Run T `--filter DataProtectionPromptKeyProvider`. This proves dictionary construction only.
- [ ] Write initialization/recovery state-machine tests first. `uninitialized + verified configuration + no protected rows` may deliberately initialize after explicit enablement. `ready + itemNotFound` or any existing ciphertext with missing key must report recoveryRequired and never create/reset. An unauthorized-group read may also return itemNotFound, so that status alone never authorizes initialization. Duplicate add reads and validates the winner without deletion. Crash after item creation but before ready SQLite commit reuses only the exact valid namespace/key and reconciles an uninitialized empty store. Crash after ready commit reopens with same key. Unknown, interaction-disallowed, cancelled, authentication-failed, malformed, unsupported version or unavailable statuses preserve all ciphertext and return failure. No automatic rotation or delete-key recovery. Run T `--filter PromptKeyInitialization`.
- [ ] Implement only after those reds. Use `SecItem` Data Protection calls, fixed explicit real authorized group, no legacy or synchronization shortcut. Verify configuration before first creation; never perform Keychain calls while holding the store lock. Recheck generation/lifecycle before committing ready state. Do not delete an item after SQLite failure. Production key generation occurs only inside this separately authorized initialization path, never the unsigned lane.
- [ ] In genuine signed/provisioned bundles, create/read a dedicated synthetic item as broker. Each of the three distinct same-team signed worker identities must fail to read/update/delete it and broker must still read original bytes afterward. Do not assert one exact OSStatus for all denial cases. Inspect actual entitlements/profile authorization and prove no shared application group, database access, network entitlement or private-key group was accidentally conferred. No ordinary `swift test` host can stand in for the signed broker. If worker identities are not yet available, record the negative isolation gate as blocked and keep production activation gated.
- [ ] Verify key/item behavior across broker restart, screen lock/unlock, user-session conditions, cancellation and restored/copied database. Clear broker-held key/plaintext references according to the selected policy. Copying ciphertext to a different Mac is not a recovery mechanism for a device-only key. Test real signed prompt-library journey with synthetic content and networking disabled, separately record keyboard/VoiceOver/light/dark/reduced-motion results. Bundles/launches and any OS restart require separate authorization, absent from the current task.
- [ ] Only after the applicable signed positive/negative/lifecycle gates pass, replace unsigned unavailable composition with the production provider and record verified build identities. The app still fails closed whenever the provider is unavailable. Commit security adapter/gate evidence separately. Queue remains waiting until roadmap slice 3, regardless of signing success.

## 5. Acceptance and failure matrix

| ID | Requirement and exact observation | Planned evidence | Blocking boundary |
| --- | --- | --- | --- |
| P1 | Capture appears only in Inbox; Save moves to Library; title/tags/project/favorite persist | Tasks 1, 5, 8, 9 | Signed UI journey not substituted by model tests |
| P2 | Edit twice yields immutable v1/v2/v3; editing draft does not overwrite Library/history | Tasks 1, 5, 9 | None for fixture lane |
| P3 | Archive/restore preserves versions and initial/saved membership across two reopens | Task 5 | None for fixture lane |
| P4 | Required vars/context rules, exact one-pass preview, 10/1 MiB/2 MiB limits, no expression execution | Task 2 + acceptance | Full file attachment import is not offered |
| P5 | Literal case-insensitive title/body, exact AND filters, scope/normalization frozen, stable 50-row pages and total | Task 6 | >1,024 candidates honestly rejected, not truncated |
| P6 | Missing/duplicate/unmatched/stale search IDs rejected; corrupt candidate cannot disappear silently | Task 6 | No worker search execution claimed |
| P7 | Queue retains explicit saved version, exact inputs, digest and output across edits/restarts | Tasks 7, 9 | All entries waiting, execution deferred |
| P8 | Body/context/resolved/retained values/history encrypted before SQLite; no fixture provider in shipping composition | Tasks 3, 5, 7–9 | Signed key custody separate |
| P9 | Key failures/corruption preserve bytes and explain recovery; reminder service works with unavailable prompt key | Tasks 3, 5, 8, 10 | Shared SQLite structural corruption can affect all storage |
| P10 | Only broker reads private Data Protection item; workers cannot read/change/delete; lock/restart behavior verified | Task 10 | Signed/provisioned actual hosts, not yet verified |
| P11 | Existing reminders, notices, policy, migration/conflict/recovery tests remain green | Full T after each commit | Historical 134-test checkpoint is not a new result |
| P12 | Accessible native journey and truthful default runtime/availability | Tasks 8–10 | Model/compile evidence versus signed manual/UI evidence clearly separated |

### Restart and corruption fixtures

1. Close/reopen after capture, Save, each edit, archive, restore and enqueue. Reopen twice. Same IDs, revisions, tags, state, protected content and queue references, no duplicates.
2. Fail before transaction, after INSERT, before reference update and before COMMIT. Old state and generation intact, no orphan row or partially moved Inbox item. Reopen and retry deliberately with current revision.
3. Two concurrent edits/saves/enqueues. One revision winner, immutable history, queue idempotency preserved. Stale preview cannot silently queue a changed source/input.
4. Flip ciphertext/tag/nonce, substitute another record/version/store/field envelope, change key ID, use wrong/malformed key, truncate/oversize envelope or corrupt decoded UTF-8. No unauthenticated content returned, bytes preserved, no repair-by-empty/rekey.
5. Key absent for ready store, copied database without key, unsupported envelope/schema, failed SQL write including injected disk-full. Explicit unavailable/recovery state, no destructive reset and no false success. Preserve editor input only in trusted memory while session permits it.
6. Key unavailable while reminders list/save/reconcile and metadata inspection run. No prompt error escalates into notification permission changes, worker execution or network access. Shared structural database corruption is reported honestly.
7. Search generation changes between scope capture, decrypt, publication and page access. Stale result rejected; corrupt/unreadable candidate fails whole requested body search. No partial-count success.
8. Key creation → SQLite initialization interruption is fake-state-machine evidence in unsigned tests only, followed by real signed synthetic restart evidence when Task 10 is authorized. No atomicity claim across Keychain and SQLite.

## 6. Explicit exclusions and safe follow-through

- No execution, scheduling engine for prompts, job attempts, leases, approvals engine, worker spawning, runtime plugin, language model, shell, network, voice, or consequential action. Eligibility is stored only. No “completed” indicator for preparation.
- No general file attachment import in this slice. Explicit selected/pasted text snapshots exercise canonical context semantics without silently reading user files. No external export controls are added before destination-specific approvals exist.
- No destructive prompt delete or delete-all control in this minimal stage. Archive is labeled archive, never delete. Future data controls must remove records, versions, attachments, queue snapshots and derived caches after explicit confirmation and follow the canonical ordered erase protocol. Inspection/correction are covered by history/editing. Export/deletion remain release requirements, not silently declared delivered here.
- No automatic key rotation, reset, cloud sync or recovery key feature. Recovery retains ciphertext and explains missing prerequisites. No promise of forensic erasure from SSDs/backups/exports, universal memory erasure, protection against a compromised broker/admin, or cryptographic filesystem rollback prevention.
- No production feature advertisement until the signed boundary is verified. Domain/codec/storage/model success is valuable implementation progress, not an authorized personal-data workaround.

## 7. Research review, blockers and current validation record

Local review found the supplied research consistent with the controlling spec and inspected architecture: built-in CryptoKit is the proposed primitive, explicit test injection is separable from shipping composition, the Data Protection selector/private non-synchronizable group are mandatory, unauthorized reads can be ambiguous, and signed broker/worker evidence is indispensable. Accessibility choice, exact IDs, initialization, rotation/recovery and packaging remain separate decisions/gates. Preserve the research's distinction between source claims and actual tests.

**This session's review is offline.** The research's prior Apple-document fetches are its author's reported provenance. No links were re-fetched and no account/signing/Keychain state was independently inspected here. Accept the note as qualified supporting research, not newly verified live Apple behavior or evidence that prerequisites are missing. The prior toolchain and signing observations remain historical.

Current blockers for production availability: actual authorized signing/profile/group identity; selected accessibility/session lifecycle policy; signed positive and same-team negative worker tests; genuine lock/restart/recovery tests; native signed UI/accessibility journey. Full Xcode and account asset readiness are unverified in this session, not asserted absent. Neither a passing package build nor an ad-hoc signature clears any of these gates.

Planning validation is documentation-only: inspect canonical spec/roadmap, research, Package.swift, store/schema/records, app/model/sidebar, scripts and reminder tests/evidence; cross-check paths, dependency direction, contracts, acceptance mapping, placeholder absence and diff hygiene; inspect staged file list and commit only this plan plus the reviewed research. No implementation tests, cryptographic tests, builds, bundles, launches, network requests, live Keychain operations or installations are performed by this planning task. Future checkboxes above remain unchecked until observed execution.

**Observed documentation checks before commit:** local Python assertions passed for 10 ordered tasks, 12 acceptance mappings, 11 exact canonical constraint quotes, existing integration paths, resolving local Markdown links, balanced code fences, no unfinished prose markers, no checked future tasks, and exactly one coordinator research-review section. `git diff --cached --check` passed. The staged scope was exactly this plan and the research note. These checks validate documentation structure and consistency, not executable Swift or the proposed cryptographic/security behavior.
