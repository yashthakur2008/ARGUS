# Persistent Voice Experience Implementation Plan

> **For agentic workers:** Use test-driven-development and scoped commits. Independent owners share this repository, not worktrees. Never edit another owner's files or launch/install/register/login/capture audio from tests.

**Goal:** User-approved persistent opt-in listening and login toggles, offline spoken activation responses, and polished bounded visual feedback.

**Architecture:** Preserve the local activation service. Add a presentation voice coordinator that owns persisted user intent, transient suspension reasons and speech/capture exclusivity. Replaceable native speech and login adapters expose injectable boundaries. App composition alone wires lifecycle events and views.

**Tech Stack:** Swift 6, SwiftUI/AppKit, AVFoundation local synthesis, ServiceManagement SMAppService, existing on-device Speech recognition. No external packages.

**Spec:** User approved September18: persistent listening while app runs, restart/unlock resumption after explicit preference, login opt-in, independent disable toggles, offline macOS TTS and dynamic emerald visuals. Prior safety constraints remain except the explicit every-launch-enable policy is superseded by the approved remembered opt-in.

## Global constraints

- Default all persistent microphone and login options OFF. Never register a login item or request audio permission during initialization or automated tests.
- Always-listen OFF immediately stops capture and speech and invalidates late callbacks. Explicit Stop listening also disables remembered always-listen so unlock cannot undo mute.
- Suspension for sleep/lock/session switch stops both capture and speech synchronously but preserves intent. Resume only after all relevant suspension reasons clear. Wake alone must not override known lock/session suspension.
- Automatic resumption must never prompt for permissions: check existing microphone/speech authorization first; if unavailable show an explicit Enable/review requirement.
- Local-only speech recognition stays required. Offline speech output uses installed macOS voices through a replaceable adapter. No network, keys, ElevenLabs request or hidden LLM. ElevenLabs remains optional future provider requiring secure credential setup and transmitted-text consent.
- Pause capture before speaking, resume only after current speech completion if current user intent and lifecycle permit. Stop, error, superseded completion, changing mode or disabling speech cannot cause stale capture restart. Bound spoken text, do not log it.
- Login UI reflects real OS registered/requiresApproval/unavailable state, not just saved preference. Registration/unregistration only from user toggle, errors visible. No helper that survives explicit Quit.
- Animate briefly, not continuously while idle. Reduce Motion system preference OR app toggle disables animation. Overlays stay nonactivating, clickthrough, bounded, multi-display and teardown-safe.
- Root alone builds/installs after tests and review, leaving microphone/login preferences untouched until user acts.

## Task 1: Voice lifecycle, local TTS and preferences

Owner: new Platform SpeechOutput.swift and NativeSpeechOutput.swift, new Presentation VoiceExperienceController.swift and VoicePreferences.swift, ActivationController.swift if necessary, corresponding new tests. Do not edit App/Settings/Today/overlay files.

Public boundary to expose: @MainActor SpeechOutput protocol with isSpeaking, completion callback or equivalent generation-safe request IDs, speak(_ text:String), stop(). NativeSpeechOutput uses AVSpeechSynthesizer and on-device installed voice selection, no network. State callback must distinguish actual completion/cancellation/error. Preserve injection for tests.

Public coordinator API to freeze with root immediately: init(activation:ActivationController, speech:any SpeechOutput, defaults:UserDefaults, permissions: injected noninteractive checker); alwaysListen:Bool, spokenResponses:Bool, isSpeaking:Bool, statusText:String; setAlwaysListen(_:) async, setSpokenResponses(_:), stopListening(), suspend(reason:), resume(reason:) async, restoreIfEnabled() async, handleActivation(_ trigger:ActivationTrigger), previewSpeech(). Mode persistence must be explicit and never silently change current mode. Defaults clap compatibility is allowed; user can select name mode.

- [ ] Write fake-boundary tests first: default OFF/no starts; persistence/reopen; OFF while permission pending; sleep/lock during request/speech; wake while still locked; completion after mute; superseded completion; denied auto permissions does not call start/request; only one speech at a time; TTS false produces no speech.
- [ ] Run actual behavioral red before implementing coordinator. Tests must not produce real sound or permissions.
- [ ] Implement persisted intent separated from transient state. Startup auto path checks authorization without prompting. Explicit enabling can request permissions through existing service. Safely handle same-session capture stop/restart and preserve legacy enable/stop tests.
- [ ] Speak a short fixed response such as "I'm here." on valid activation and fixed preview sample only, not arbitrary stored personal data. Native completion/cancellation fences prevent loops, include a short cancellable post-speech cooldown before capture resumes if needed.
- [ ] Run focused tests then full Swift Testing and plain build. Commit scoped files, report precise API and limits. No bundle or app launch.

## Task 2: Login adapter and settings controls

Owner: new Platform LoginItemService.swift, new Presentation LoginItemController.swift and VoiceSettingsView.swift, new tests only. Root integrates view into Settings.

Public API: @MainActor LoginItemService protocol status:LoginItemStatus and setEnabled(_ enabled:Bool) throws; statuses disabled/enabled/requiresApproval/unavailable. NativeLoginItemService wraps SMAppService.mainApp, re-reads status after calls and handles unsupported/development configuration honestly. LoginItemController init(service:), statusText, isEnabled, isWorking, setEnabled(_:) with error reporting, refresh(). Expose VoiceSettingsView(voice:VoiceExperienceController, login:LoginItemController) after Task1 API confirmed; no duplicate always-listen state. Wait for interface if not ready, tests/service first.

- [ ] Tests first using fake service: initialization queries only, no registration; true calls register once; false unregisters; requiresApproval not reported as working enabled; thrown error preserved and actual status refreshed; repeated refresh does not mutate OS.
- [ ] Implement native ServiceManagement adapter and independent UI controls Always listen, Spoken responses, Launch at login, test voice, Stop. Explain microphone and login are separate permissions. Explicit Start once remains available through existing controls.
- [ ] Test controller errors and state, compile real adapter with no live SMAppService mutation. Commit only owned paths and report root integration signature.

## Task 3: Dynamic edge glow and compact status orb

Owner: ScreenEdgeGlow.swift, new Presentation VoiceStatusOrb.swift, corresponding tests; AppearanceSettings.swift only for persisted reduceMotion override if required (notify root). Root integrates orb.

Keep show(color:) and hide() compatible. Add show(color:reduceMotion:) if needed, native system reduce-motion always dominates. Add brief gradient/soft-edge pulsing effect using bounded Core Animation layers or equivalent, no renderer/timer at idle. Static fallback may preserve current geometry. VoiceStatusOrb accepts listening/speaking/off state and accent/reduceMotion flag, uses honest fixed state animation (not fake audio waveform), no microphone access.

- [ ] Test policy first: reduced motion disables animation, finite duration, same passive styles, cancellation epoch, invalid sizes, no endless timers.
- [ ] Implement tasteful emerald gradient glow and compact orb with clear status label, restrained state transitions and accessible text. Preserve clickthrough/focus and multi-screen behavior.
- [ ] Full focused tests/build, scoped commit. No native panels launched by worker.

## Task 4: Root composition and lifecycle integration

Owner: ArgusApp.swift, ActivationSettingsView.swift, TodayView.swift, SettingsView.swift, ActivationSuspensionMonitor.swift if needed, tests/docs.

- [ ] Tests first for lifecycle resume signals and synchronous suspension. Track independent sleep/display/lock/session reasons, no wake-while-locked restart. Preserve existing monitor initializer compatibility.
- [ ] Wire one coordinator/speech provider/login controller per app, no activation during initialization. Hook actual app launch and lifecycle after initialization, and permission checks before auto start. Root menu Stop calls coordinator stop so persisted opt-in is disabled. Quit synchronously stops all without changing remembered preference.
- [ ] Add approved settings and orb without duplicating controls or adding dense dashboard. Change old each-launch/off wording to match opt-in persistence. Expose Reduce motion override (system setting always respected).
- [ ] Independent privacy/lifecycle review and complete tests/build. Fix concrete findings with regression tests.
- [ ] Root native demo preview/theme only, no mic/login mutation. Verify installed update path/code identity and avoid replacing running executable. Update installation with backup, verify signature and resources, report untested real audio/login behavior. Commit docs and code separately.

## Verification command

Use existing /Users/yashthakur/.jcode/scratch/argus-swift-6.1.2/expanded/swift-6.1.2-RELEASE-osx-package.pkg/Payload/usr/bin/swift test --disable-xctest --enable-swift-testing. No downloads or system tool changes. Coordinator runs scripts/verify.sh only after workers freeze. Signed App Store, real login launch and physical speech remain external gates unless explicitly exercised.

## Reviewed integration refinements

- Public macOS session APIs do not expose reliable initial lock state. Seed a separate startupUnverified suspension. Only explicit Start/Always-listen user action or an observed unlock clears it. Session-active or wake alone does not. This means cold login launch can remain paused until unlock or an explicit Start, rather than silently claiming immediate capture. Distributed lock/unlock notifications are an existing platform convention, not an SDK-declared public lock-state contract.
- UI enable requests must capture intent synchronously before queuing async work. A later Stop invalidates the queued enable. Automatic start uses a distinct authorized-only audio service path that never invokes requestAccess, not just a prior authorization check.
- Task1 freezes VoiceSuspensionReason as systemSleep/displaySleep/screenLock/sessionInactive/startupUnverified. Root lifecycle bridge keeps per-reason event generations, so queued old unlock cannot undo new lock, while independent sleep/display wake signals are not lost.
- Task3 freezes VoiceStatusOrb(state:accent:reduceMotion:) with off/listening/speaking, ScreenEdgeGlowController.show(color:reduceMotion:) and setReduceMotion(_:), AppearanceSettings.reduceMotion and setReduceMotion(_:).
- Prompt-library work is checkpointed at ea91235 and paused for this higher-priority user request. No prompt storage or key gate is changed by voice work.
