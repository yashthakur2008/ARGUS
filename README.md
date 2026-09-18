# ARGUS

A native macOS, local-first assistant for reminders, reusable prompts, and bounded parallel work. Calm interface, explicit permissions, verified results.

**Status: working native reminder and activation prototype, not the complete MVP or an App Store release.** The local application stack uses SwiftUI, deterministic Swift domain logic, system SQLite, and native platform adapters. It has no runtime generative language model, cloud backend, shell agent, or Jcode dependency. Optional name detection uses Apple's on-device speech recognizer, never a hosted assistant.

At the latest independently verified activation checkpoint, the full Swift Testing suite passed (**190 reported, with two opt-in profiling tests skipped**), as did release bundling/signature checks. The installed app passed two-display preview, focus preservation, theme persistence, and microphone-off restart checks. Physical clap/name recognition remains untested. See the [activation and installation evidence](docs/verification/2026-09-18-local-activation.md). The previous reliability checkpoint also passed 400 repeated concurrent-startup scenarios, and separate release profiling passed both opt-in tests. Earlier isolated native demonstrations exercised creation, Quit/relaunch, exact ten-minute snooze, delete confirmation, notice dismissal, and persisted quiet hours. Actual notification delivery and release sandbox/signing remain unverified. See the [native evidence](docs/verification/2026-09-17-reminders-slice.md) and [latest reliability checks and limitations](docs/verification/2026-09-18-improvement-batch.md).

## Available in the prototype

- Typed finite reminder commands, plus native creation/editing controls.
- One-time reminders, weekday recurrence, stored time zones, multiple alert offsets, and snooze without changing the deadline.
- SQLite persistence with optimistic revisions, corruption checks, transactional notification generations, and restart reconciliation.
- A compact Today view with Now, Approaching, All reminders, and real settings.
- One-use, expiring delete confirmation bound to the reviewed reminder.
- Explicit notification opt-in, generic notification previews, and separate saved/pending/scheduled status. Scheduled never means observed delivery.
- Opt-in clap or “Argus” detection, brief click-through screen-edge feedback, and a menu-bar microphone/stop control.
- Original green guardian app icon and locally saved custom accent/glow colors.

Persisted quiet-hours settings, notice history with independent dismissal, and bounded missed-alert recovery are implemented. Recovered notices record due times, not proof of notification delivery. One-time notifications are planned beyond the recurring seven-day window.

## Clap, name activation and appearance

Open **Settings → Local activation**, choose **Clap**, **Say Argus**, or **Clap or say Argus**, then press **Enable listening**. Listening is off on every launch, and no permission prompt appears until you enable it. Clap-only needs microphone permission. Name activation additionally needs Speech permission and supported local US English speech resources. Missing support produces an unavailable state, with an explicit clap-only choice rather than a server fallback.

Activation shows a brief colored border around connected screens. It does not execute spoken commands, alter reminders, or generate a spoken reply. **Preview glow** works without microphone access. In **Appearance**, select a preset or enter a six-digit hex color to change the accent and glow.

The sidebar and menu bar expose listening status and **Stop listening**. Closing the window does not stop an enabled session, but Quit, sleep, screen lock, or session deactivation do. Re-enable manually after returning. There is no login helper. Audio buffers and recognition text are transient in memory, not saved or logged by ARGUS. Sharp sounds can be mistaken for claps; physical detection depends on microphone, room noise, and speech recognition quality. Normal local speech tasks renew within the same enabled session; errors stop listening and require an explicit retry.

The icon is original project artwork, not an extracted game asset. It is built locally from the checked-in PNG with macOS tools. Image generation was a development activity, not a runtime dependency.

## Build and run

Requires macOS 14 or later, a **working Swift 6.1 toolchain and macOS SDK**, and Apple's standard command-line signing tools. Verification on this machine is Apple Silicon only. There are no external Swift package dependencies.

```sh
# Optional: choose a working toolchain instead of the selected system swift.
# export ARGUS_SWIFT=/absolute/path/to/swift
bash scripts/verify.sh
open build/ARGUS.app
```

`verify.sh` runs the tests, creates a release-mode development app, verifies its ad-hoc signature/plist, and rejects private build-machine runtime library/search paths. It does not install, launch, notarize, or publish the app. For bundling alone, use `bash scripts/build-dev-app.sh`.

GitHub Actions runs the same script on a clean `macos-15` runner with Xcode 16.4 selected explicitly, for pull requests and pushes to `main` or `feat/**`. The workflow has read-only repository permission, does not persist checkout credentials, and uses no signing secrets. A passing run verifies a development bundle, not notification delivery or App Store eligibility. Runner images can change independently of the selected Xcode version.

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
