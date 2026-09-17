# ARGUS

A proposed native macOS, local-first assistant for reminders, reusable prompts, and bounded parallel work. Calm interface, explicit permissions, verified results.

**Status: design and release planning, not a working application.** The native Swift/SwiftUI/SQLite direction and three deterministic workflows are agreed. The written design and phased plan await review before implementation. No runtime language model, cloud backend, shell agent, or hidden development-tool dependency is proposed.

## Review documents

- [Consolidated design](docs/superpowers/specs/2026-09-17-argus-native-macos-design.md)
- [Phased delivery and verification roadmap](docs/superpowers/plans/2026-09-17-argus-delivery-roadmap.md)
- [Native experience research](docs/research/native-experience.md)
- [macOS release and isolation research](docs/research/macos-release.md)
- [Security and recovery research](docs/research/security-recovery.md)

The consolidated design takes precedence over alternative defaults in supporting research.

## Intended MVP

- Typed deterministic commands, local reminders, and system notifications.
- Versioned prompt library with tags, search, variables, and queued preparations.
- Up to three isolated hands: prepare a prompt, search the library, and assemble a deadline briefing.
- Visible results and activity, consequential-action approval, persistent state, and Stop All.
- Optional replaceable speech output. ElevenLabs is disabled until the user supplies a credential securely and enables it with disclosure.

## Development and release gates

Implementation proceeds in vertical slices: reminders, prompts, worker queue, orchestration, optional voice, calendar adapter, and reliability/privacy/release verification. Each slice must include tests, a demonstration, failure/restart checks, a safety review, and a scoped commit.

Full Xcode was not found in the standard application locations on the development machine. Command Line Tools are installed, but do not establish signed app, XPC isolation, UI-test, archive, or App Store readiness. Apple developer membership, signing/provisioning, metadata, privacy disclosures, archive validation, and user-authorized submission are separate release requirements.

Closing an ARGUS window, quitting ARGUS, and turning off the Mac are different lifecycle events. System-scheduled notifications can outlive the UI. Ongoing computation after explicit Quit requires a separately consented and verified background helper. No hard-real-time delivery promise is made across sleep, shutdown, Focus, or permission denial.

Jcode development progress is checkpointed in the durable initiative `argus-native-macos-assistant`. Headless sessions depend on the detached server staying alive. Its documented all-clients-closed idle timeout means uninterrupted development after closing every client has not been established. This is a development limitation, not a runtime dependency of ARGUS.
