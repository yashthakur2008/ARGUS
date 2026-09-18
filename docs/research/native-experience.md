# ARGUS native experience

Design recommendation · 2026-09-17 · Design only, not an implemented or tested application.

## Intent and approach

ARGUS is a quiet native macOS workspace for preparing prompts and keeping explicit commitments visible. It executes local rules, not conversation or inferred intent. No runtime LLM, fake chat transcript, typing indicator, synthetic confidence score, or claims that it understands, thinks, or autonomously decides.

**Recommend a command-first workspace:** a persistent command bar, a short Now section, and an Approaching section. Use ChatGPT's generous reading column and Notion's restrained hierarchy as references, not copied branding or chat composition. ARGUS's distinguishing feature is a visible chain from command to resolved inputs to verified output.

Alternatives considered:
- A launcher-only utility is fast but hides approval context and prompt history. Use a command palette inside the workspace instead.
- A dashboard exposes everything but creates noise and makes three bounded workers look like autonomous agents. Reject persistent metric cards and multi-column activity feeds.

No blocking design questions remain. Defaults below are proposals for implementation review, not additional user approvals or evidence of working software.

## Scope contract

**MVP:** local prompt Inbox and Library, versioned templates, explicit pasted or user-selected plain-text context, manually entered deadlines, local approval requests, deterministic commands, an in-app notification center, optional macOS notifications after permission, and at most three active Hands. A Hand is a bounded local job, not an agent or persona. Persistent local data works without an account or network connection.

Only three initial work types are approved:
1. Prepare a prompt from variables and selected context, producing text for review and explicit copy/save.
2. Search the local prompt collection with literal terms and filters.
3. Produce a fixed-rule deadline/approval briefing from locally recorded items.

Approving a local export does not approve a new workflow. Never send a prepared prompt to a model, launch shell commands, execute template content, read arbitrary folders, scrape the screen, or monitor the clipboard. Treat imported text as data, even if it contains instructions. Local approvals authorize only the displayed local operation.

**Later, separately scoped:** calendar integration and its permissions, external actions, additional workflow types, optional global launcher shortcut, and opt-in text-to-speech. No microphone, wake word, dictation, or audio recording in the first slice. Do not show empty calendar connectors or a decorative microphone in MVP.

## Window and visual language

Default window approximately 980 × 720 pt, minimum 680 × 520 pt. Native title bar and toolbar, restrained SF Symbols, system typography, real macOS menus and standard controls. Main reading column has a 760 pt maximum width with 24–32 pt margins. Sidebar is approximately 176 pt and can collapse. At minimum width collapse it automatically, with all destinations still available in the toolbar and View menu. Detail replaces the main content rather than opening a permanent third column.

```text
┌ ARGUS                                    Hands 1/3   Stop all ┐
│ Home       │  Type a command…                         ⌘K      │
│ Prompts    │                                                  │
│ Approvals  │  Now                                             │
│ Notices    │  Review prepared weekly update           Review  │
│            │  Release sign-off · overdue 25 min        Open   │
│            │                                                  │
│            │  Approaching                                     │
│            │  Tomorrow · budget draft · 10:00                  │
│ Settings   │                                                  │
└────────────┴──────────────────────────────────────────────────┘
```

Use a single muted accent for primary action and selection. No gradients, mascot, moving orb, ornamental graphs, or status-color walls. Content rows have title, one-line reason/time, and one primary action. Secondary actions appear in a labeled menu, never only on hover. Home shows at most five rows per section with a truthful remaining count and Show all. No statistics card when nothing is happening.

Light appearance uses warm-neutral system backgrounds and a slightly separated sidebar. Dark appearance uses system dark surfaces, not pure black with bright white borders. Use semantic dynamic colors, not fixed palette substitutions. Respect Increase Contrast and Reduce Transparency. Color is redundant with text and symbols. Body text defaults to 14 pt or larger, supporting app text-size choices without truncating controls. Primary hit regions are at least 28 × 28 pt with clear focus rings.

## Screens and acceptance criteria

Criteria in this document are future implementation acceptance tests. They have not been executed against a product.

### 1. Home: Now and Approaching

Now contains overdue items, deadlines within the next 24 hours, approvals requiring a decision now, and running or blocked Hands. Approaching contains dated items more than 24 hours and at most seven days away. Later and undated items remain in their source lists, not on Home. Each item appears once, with secondary badges if it meets multiple rules. Stable ordering: overdue by oldest due, ready approvals by oldest request, running/blocked work by start time, then upcoming deadlines by due time, with ID as tie-breaker. Show why each item is present, for example “Due in 40 min” or “Approval required.” These are fixed rules, not an importance prediction.

MVP deadlines are explicit local records with title, due instant, timezone, optional local source link, and done state. A small Add deadline sheet and All deadlines list live under Home, not a new dashboard. Completed records leave both sections. Past-deadline entry is allowed with an overdue warning. The application clock reevaluates sections on launch, wake, edits, and minute boundaries. Display timezone when different from the Mac's current timezone.

**Acceptance:** fixtures at now, +24 hours, +24 hours plus one second, +7 days, and +7 days plus one second enter exactly the defined sections. Done records vanish from Home but remain in history. A blank installation says “Nothing needs attention” with Add deadline and Browse prompts, not sample tasks. Saving a deadline requires an unambiguous date/time and previews its timezone. No calendar access is requested. Reopening preserves manually entered records.

### 2. Command bar and results

Use the placeholder “Type a command…” and a compact Examples affordance. Suggestions are a finite verb/argument list, labeled Commands, not generated answers. The field parses visibly into verb and arguments. Enter opens a plan or search result, never silently exports, discards, or resumes stopped work. Escape closes suggestions first, then returns to the previous screen without losing a draft. Parsing failure stays inline and keeps the input intact.

Canonical examples, where quoted values allow spaces:

```text
help
prepare prompt:p-014 version:3 var.project:"ARGUS" context:c-008
search prompts "release notes" tag:work status:library
briefing from:2026-09-17T14:00-07:00 until:2026-09-18T14:00-07:00
open approval:a-023
snooze notice:n-018 for:30m
reschedule deadline:d-006 at:2026-09-18T10:00-07:00
stop all
```

Grammar: `verb [noun] ["literal query"] [key:value ...]`. Expose only the documented verb-specific keys. Quotes support escaped quotes and backslashes. Duplicate or unknown keys are errors, not ignored. Template variable names must match the selected version. IDs are stable and displayed in details. Verb matching is case-insensitive, literal search is case-insensitive across title/body, tags are exact case-insensitive matches, all filters combine with AND, and identifier matching is exact. No fuzzy execution, implicit shell syntax, variable expressions, or free-form language interpretation.

Convenience name lookup is allowed only through visible selection: `prepare prompt:"Weekly update"` with two matches shows title, folder, ID, and version. No job starts until a match is chosen. Missing required values open a form and preview, never get invented. Dates without offsets use an explicit timezone picker and confirmation. Reject ambiguous dates such as `03/04` with examples. For daylight-saving repeated/nonexistent times require an offset choice or a valid replacement. `briefing` with no arguments visibly proposes now through the next 24 hours before running. Date-only deadlines must get an explicit time, never silently mean midnight.

**Acceptance:** every example parses into the expected typed action. Unknown verbs show help without side effects. Duplicate names force selection. A malformed escape, unknown key, missing variable, or ambiguous time cannot enqueue work. User-provided context containing command-like text never executes. Search returns local matches only, with result count and matching excerpt. Zero matches says so and offers Clear filters. No network requests occur.

### 3. Prompts: Inbox, Library, detail

A single Prompts destination has Inbox and Library tabs, search, and New prompt. Inbox contains captured drafts awaiting review, not a second notification feed. New/imported text stays Draft until title, body, and variable definitions validate. Library contains explicitly published versions. Archive is a reversible filter, not deletion. Empty Inbox says “Inbox clear.” Empty Library offers Create prompt and Import text, with no fabricated examples.

Detail is a readable editor with title, tags, body, variables, and explicit context attachments. MVP variables are literal `{{name}}` substitutions with declared text types, optional defaults, and required markers. There is no expression engine or nested expansion. Reserve `{{context}}` for concatenating selected text in the user's visible order, separated by two LF characters. If no context is selected it resolves to empty text. If context is selected but the template has no context token, block preparation and offer to insert the token explicitly. Preserve input text bytes after UTF-8 validation, and never recursively resolve tokens inside substituted values or context. The preview makes separators visible on demand. Show undefined tokens and unused variables. Context enters through a file chooser or deliberate paste, is previewed and removable, and never comes from an ambient selection in another app. Declare proposed MVP limits: UTF-8 text only, 10 context items, 1 MiB total input, 2 MiB resolved output. Validate before enqueueing and explain exceeded limits without partial truncation.

Lifecycle: **Draft → Published v1 → new Draft → Published v2**, with Archive/Restore independent of version. Published versions are immutable. Restoring an old version creates a new draft and publishing increments the version. History shows authored time, variable schema and body diff, and associated run receipts. Publishing a draft does not change queued or completed runs.

Prepare flow: choose a published version → fill variables → select context → inspect resolved preview → Queue preparation → inspect verified result → Copy or Save to chosen file. Preview shows the exact resolved text plus a separate input manifest: version, values, context names, byte counts, and snapshot fingerprints. Metadata is not silently inserted into copied text. Queue order is FIFO among ready jobs. A queued item can be cancelled or reopened as a new preparation, but its frozen inputs cannot mutate in place. Queue status belongs to a run, not the prompt itself.

History retains immutable inputs/output locally until the user explicitly removes the run. Explain this before first preparation. Removing an unused draft is reversible via Undo. Removing history containing context needs confirmation and warns that already copied/exported text cannot be recalled. Do not claim secure erase or special encryption beyond actual platform storage protections.

**Acceptance:** validation blocks publishing unresolved schema errors. Identical frozen inputs generate byte-identical output. Editing v3 or its original context after queueing does not alter the snapshot. Restoring v1 never overwrites v3. Copy matches the preview bytes. Exceeding input/output bounds fails before publication with no truncated result. Archive preserves history and Restore recovers the item. Denied file access preserves the draft and offers Choose file again without requesting full-disk access.

### 4. Hands: bounded jobs, queue, and receipts

The toolbar shows **Hands 0/3**, not three empty cards. Clicking opens a compact sheet with up to three active rows and a collapsed queued list. With no work it says “No active work” and offers Prepare prompt, not a spinner. Start with a conservative default of one concurrent job, allow 1–3 in Settings, and never exceed three. Waiting for user approval releases an active slot. A row displays the actual operation, stage, elapsed time, and Cancel. No invented percentage or “thinking.” State machine: **Queued → Running → Verifying → Complete**, with **Awaiting approval**, **Blocked**, **Failed**, and **Cancelled** explicit alternatives. Failure and cancellation never imply success.

Each workflow has meaningful bounded output:

| Work type | Output and bounds | Verification before Complete |
| --- | --- | --- |
| Prepare | One resolved UTF-8 artifact plus input manifest, within declared size limits | All required variables resolved, literal substitutions correct, snapshot/version matches, byte count and fingerprint recorded |
| Search | Up to 50 results per page, total match count, stable title/ID ordering and literal snippets | Every result exists in the searched snapshot and satisfies every filter, pagination has no duplicates |
| Briefing | Due/overdue deadlines and pending approvals from the fixed time window, count plus paginated rows, never prose conclusions | Every entry links to a source record and names the matching rule, sorted deterministically, no invented urgency |

Briefing includes overdue incomplete records regardless of the window start, due records within inclusive start/end, and pending approvals as of the snapshot. Deduplicate by record ID. Show source snapshot time prominently. A changed source creates a “Sources changed” banner and a Refresh action, not silent rewriting of an old receipt. Search and briefing receipts identify the snapshot/filter set without duplicating unrelated document content.

Each run has a 30-second execution budget after leaving the queue. Limit failure becomes Failed with a precise reason and explicit Retry, never an unbounded background loop. A cancelled or timed-out job cannot publish late output. Complete requires a receipt: run ID, type, frozen input reference, start/end time, output reference, and verification checks. “Prepared locally” is truthful. “Sent,” “handled,” and “done for you” are not.

**Acceptance:** with five enqueued jobs and concurrency set to three, only three run and FIFO resumes as slots free. Approval-waiting work does not monopolize slots. Injected missing inputs, timeout, and failed verification produce no Complete receipt. Cancelling during verification prevents output publication. Restart marks interrupted work as Interrupted and requires explicit retry, rather than pretending it completed. Jobs whose outputs no longer apply can be discarded without modifying source prompts.

### 5. Approvals and global stop

An empty Approvals screen says “No approvals waiting” without a badge. Approvals is a quiet list with pending count and a detail sheet: operation, exact source version, destination, preview, consequences, and Approve/Reject. MVP supports local export proposals and user-recorded approval reminders. A reminder is marked Reviewed or Done, not executed. Copy after preview is itself an explicit user action. Save uses a native destination chooser and overwrite confirmation. No generic “Approve everything” and no future integrations implied by approval wording.

An executable approval is one-use and bound to an immutable operation fingerprint. Input/destination changes invalidate it and require fresh review. Pending approvals expire after 24 hours by default, visibly timestamped, and expired items cannot execute. Reject is terminal for that proposal, with a new proposal required to retry.

**Stop all** is always labeled and reachable from every screen and the app menu, with shortcut ⌘⇧. displayed alongside it. Stop is immediate and needs no confirmation: cancel active jobs, pause queue dispatch, invalidate unconsumed execution approvals, and prevent new output publication. Show “Stopped · queue paused” and a deliberate Review and resume action. Already committed local outputs remain with receipts. A write already committed before stop is not undone or misreported as cancelled. Later speech playback must stop too. Stop does not delete data or erase deadlines. Notifications are not jobs: they remain controlled separately by notification settings.

**Acceptance:** approving twice executes at most once. Approval after content/destination change or expiry cannot execute. Reject never executes. Stop from every screen blocks queue dispatch and late job publication until deliberate resume. Resume previews queued items and never reuses invalidated approvals. A race between Stop and atomic file publication produces an honest receipt for the committed operation or a cancellation with no published file, never partial content.

### 6. Notices and notification actions

In-app Notices lists timestamp, source, and reason, grouped into Today and Earlier. Its empty state says “No notices” and links to notification settings without asking for permission. Actions have distinct semantics:
- **Snooze:** hide this notice until a chosen time, default 30 minutes, without changing its source deadline.
- **Dismiss:** archive this notice only. Does not complete the task or silently approve it.
- **Reschedule:** open the source deadline editor, preview new absolute time/timezone, save the source change and update its notices. For approval records without editable due dates, omit this action and explain in details.
- **Open:** navigate to the exact source and restore keyboard focus to its heading.

Snoozing does not hide urgent source records from Home. Dedupe notice events by source and trigger. On wake, coalesce missed events into one summary rather than a burst. If the source is removed, show “Source unavailable” with Dismiss, not a broken link. macOS banners offer Open and Snooze where supported, with remaining actions in the app. Notification delivery timing is best-effort, never a safety guarantee.

**Acceptance:** Snooze changes only notice wake time. Dismiss leaves the deadline incomplete. Reschedule updates Home and invalidates obsolete scheduled notices. Open finds the correct source or shows the unavailable state. Relaunch preserves snoozes. Denying system notifications still leaves the in-app notice list fully functional. No notification permission prompt appears until the user enables system notifications.

### 7. Settings and first-use permissions

Use a standard compact Settings window: General, Notifications, Data. General includes appearance/system default, text size, and max active Hands. Data explains local storage, retained prompt/context snapshots, file access, and deliberate history removal. No account setup, onboarding carousel, or permissions wall. First launch is usable with all optional permissions denied. Clipboard copy is requested by pressing Copy, never read continuously. File selection grants only the needed file access.

Optional future Voice is a separate disabled-by-default pane. A replaceable speech provider keeps ElevenLabs optional, never tied to command parsing or correctness. Voice ID `ysswSXp8U9dFpzPJqFje` is configuration, not a secret. API credentials belong in macOS Keychain and never logs, source files, receipts, or plain preferences. Enable only after explicit external-processing consent and a valid stored key. Show the exact text that will leave the Mac before playback. Reading selected text aloud is separate from preparing it. No automatic upload of prompt history or context. On provider failure retain text and offer Retry, with no silent provider fallback. Include mute/stop and revoke/delete-key controls. Voice changes the local-only boundary explicitly, it does not add intelligence.

**Acceptance:** changing appearance follows native light/dark behavior and system default. Permission denial presents an inline explanation and narrowly scoped retry or Open System Settings. Invalid Hand counts cannot be saved. MVP contains no microphone control or audio permission request and functions offline. Later voice cannot send a request without consent plus key, uses the configured non-secret voice ID, stops on Stop all, and remains nonessential when offline or the provider fails.

## Accessibility, keyboard, and recovery contract

- ⌘K focuses the command bar from any workspace screen. ⌘1–⌘4 navigate Home, Prompts, Approvals, Notices. ⌘, opens Settings. Native Find, Copy, Undo and window shortcuts retain expected behavior. Do not bind Return to a destructive action. Context-specific shortcuts appear in menus and help.
- Tab and Shift-Tab reach every control in visual order. Lists use arrow navigation and Space/Return activation with clear selection. Sheets restore focus to their trigger. Stop is reachable without a pointing device. No keyboard trap or hover-only requirement.
- VoiceOver exposes headings, list counts, row title/reason/state and labeled actions. Announce state changes once using a polite live announcement, not every timer tick. Decorative symbols are hidden. Error messages name the field and suggest a correction. Do not rely on red/green, position, or animation alone.
- Respect Reduce Motion with instant transitions and static progress labels. Do not animate reorder while a row has focus. Large text can wrap titles, errors, and action labels. Increase Contrast must preserve focus visibility and text contrast.
- Loading uses an honest stage label only while work is happening. Empty, loading, no matches, permission denied, unavailable source, and corrupted local storage are distinct states. Corruption must not look like an empty library: preserve existing files, enter read-only recovery, and offer a user-directed export of recoverable data. Never silently reset.
- Failures retain entered text, explain the operation that failed, and provide Retry only when safe. Never retry exports automatically. Disk-full export failure leaves no partial destination and retains a verified result for retry. Closing the main window is not Quit. App Quit with active/queued work explains interruption and offers Quit and cancel or Keep open. Relaunch does not resume writes automatically.

**Cross-screen acceptance:** complete each screen's primary task keyboard-only and with VoiceOver. Check both appearances, Increase Contrast, Reduce Transparency, Reduce Motion, and largest supported text size at minimum window size. Confirm focus restoration, accessible names, no clipped required controls, and no motion-dependent status. Test offline first launch, denied permissions, disk-full save, interrupted run, missing context, source deletion, and corrupted storage without silent data loss. Verify a UI/network audit finds no model endpoint calls, microphone requests, fabricated content, or remote dependencies in the three approved workflows.

## Delivery boundaries and decisions

This file specifies interaction design only. It does not choose a persistence engine, create a SwiftUI project, install dependencies, or claim executable verification. SwiftUI screens should use native macOS components where they fit, not a web dashboard wrapped in a window.

Recommended defaults needing no blocking input: command-first Home, collapsible sidebar, literal commands, explicit context snapshots, one active Hand by default with a hard maximum of three, 24-hour Now horizon, seven-day Approaching horizon, and manual deadlines in MVP. Validate these through prototype accessibility and usability tests before implementation sign-off. Later calendar source selection, retention automation, voice commercial terms, and external-action permissions require separate scope decisions only if those features are pursued.
