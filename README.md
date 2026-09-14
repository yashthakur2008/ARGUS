# ARGUS

A native macOS, local-first assistant for reminders, reusable prompts, and bounded parallel work. Calm interface, explicit permissions, verified results.

**Status: working reminder development prototype, not the complete MVP or an App Store release.** The local application stack uses SwiftUI, deterministic Swift domain logic, system SQLite, and a native notification adapter. It has no runtime language model, cloud backend, shell agent, or Jcode dependency.

At the latest independently verified checkpoint, **94 Swift Testing tests passed**, release bundling/signature checks passed, and an isolated native-app demonstration exercised typed creation, persistence across Quit/relaunch, deadline-preserving snooze, declined deletion, and confirmed deletion. The native demonstration also found a relative-snooze timing defect, which is being fixed. Independent review found additional presentation edge cases under active repair. [Read the evidence and limitations](docs/verification/2026-09-17-reminders-slice.md).

## Available in the prototype

- Typed finite reminder commands, plus native creation/editing controls.
- One-time reminders, weekday recurrence, stored time zones, multiple alert offsets, and snooze without changing the deadline.
- SQLite persistence with optimistic revisions, corruption checks, transactional notification generations, and restart reconciliation.
- A compact Today view with Now, Approaching, All reminders, and real settings.
- One-use, expiring delete confirmation bound to the reviewed reminder.
- Explicit notification opt-in, generic notification previews, and separate saved/pending/scheduled status. Scheduled never means observed delivery.

Persisted quiet-hours settings, notice history/dismissal, and bounded missed-alert recovery are the next reminder increment. Core quiet-hours calculations alone are not advertised as an end-user setting.

## Build and run

Requires macOS 14 or later, a **working Swift 6.1 toolchain and macOS SDK**, and Apple's standard command-line signing tools. Verification on this machine is Apple Silicon only. There are no external Swift package dependencies.

```sh
# Optional: choose a working toolchain instead of the selected system swift.
# export ARGUS_SWIFT=/absolute/path/to/swift
bash scripts/verify.sh
open build/ARGUS.app
```

`verify.sh` runs the tests, creates a release-mode development app, verifies its ad-hoc signature/plist, and rejects private build-machine runtime library/search paths. It does not install, launch, notarize, or publish the app. For bundling alone, use `bash scripts/build-dev-app.sh`.

The development machine's installed Command Line Tools are inconsistent. A verified official Swift 6.1.2 package was extracted into scratch without changing system tools. Its exact development-only path and verification history are in the [evidence record](docs/verification/2026-09-17-reminders-slice.md). A clean Xcode release build is still required.

Normal launch starts empty and stores reminders in this user's Application Support/ARGUS directory. `ARGUS_DATA_DIR` is an explicit development override for an isolated data directory. Tests use disposable fixture databases and do not request macOS notification permission.

### Example commands

```text
Remind me to leave in 20 minutes
Every weekday at 8:30, show my morning briefing
list
help
edit <reminder-uuid> title Revised title
snooze <reminder-uuid> for 10 minutes
alerts <reminder-uuid> 1d,1h
delete <reminder-uuid>
```

The briefing wording currently creates a reminder, not an AI worker. Unsupported prose fails without executing it. Native controls are available without looking up UUIDs. Delete requests always require confirmation.

## Privacy and current limits

Reminder storage is local **plaintext SQLite**, not encrypted. Visible notification text is generic, but local macOS notification metadata includes the reminder title for reconciliation. No API keys or network integration are used by this slice. Actual OS banner delivery, permission/Focus behavior, sleep/wake, and release sandbox confinement have not yet been verified. Recurring scheduling currently uses a rolling window, so do not treat this prototype as your sole source of critical alerts.

Closing the window leaves the app process running. Explicit Quit stops ARGUS computation, although previously registered system notifications can remain. No login item or after-Quit helper is installed. There is no hard-real-time delivery promise across sleep, shutdown, Focus, or permission denial.

## Intended MVP, still being built

- Versioned prompt library with tags, search, variables, and queued preparations.
- Up to three isolated hands: prepare a prompt, search the library, and assemble a deadline briefing.
- Visible results/activity, consequential-action approval, durable state, and Stop All.
- Optional replaceable voice output. ElevenLabs remains disabled until a credential is supplied securely and the user explicitly enables it with disclosure.

These capabilities are not implemented by the reminder prototype. Calendar integration follows the core MVP.

## Design and release gates

- [Consolidated design](docs/superpowers/specs/2026-09-17-argus-native-macos-design.md)
- [Phased delivery and verification roadmap](docs/superpowers/plans/2026-09-17-argus-delivery-roadmap.md)
- [Reminder implementation plan](docs/superpowers/plans/2026-09-17-reminders-slice.md)
- [Approved reminder recovery increment](docs/superpowers/plans/2026-09-17-reminder-recovery-follow-up.md)
- [Native experience research](docs/research/native-experience.md)
- [macOS release and isolation research](docs/research/macos-release.md)
- [Security and recovery research](docs/research/security-recovery.md)

The consolidated design takes precedence over alternatives in supporting research. Work proceeds on `feat/reminders-slice` under the user's approved native direction and continuation instruction. A separate line-by-line review of the written spec has not occurred. Publication, paid-service, credential, and destructive-action gates remain unchanged.

Full Xcode was not found in the checked standard locations. Apple developer membership, signing/provisioning, signed XPC isolation, privacy disclosures, archive validation, and user-authorized App Store submission remain release requirements. An ad-hoc bundle is not an App Store archive.

Development is checkpointed in the durable initiative `argus-native-macos-assistant`. Headless sessions depend on Jcode's detached server remaining alive. Uninterrupted development after closing every client or sleeping the laptop is not guaranteed. This limitation is unrelated to ARGUS runtime independence.
