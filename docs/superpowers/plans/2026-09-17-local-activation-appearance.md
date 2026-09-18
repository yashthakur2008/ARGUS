# Local Activation and Appearance Implementation Plan

> **For agentic workers:** Use subagent-driven-development and test-driven-development. Implement scoped tasks, verify each, and commit only owned files.

**Goal:** Add opt-in clap/name activation, customizable green edge feedback, an original icon, and a verified local development installation.

**Architecture:** Pure activation detectors feed a replaceable macOS audio service. The presentation controller owns consent-facing state and settings. AppKit panels provide nonactivating, click-through feedback on connected displays. No command execution is triggered by a clap or wake word.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFoundation, Speech (on-device only), existing SQLite reminder stack.

**Spec:** User's September 17 request and subsequent instruction to proceed using the recommended opt-in background design. Canonical native design safety constraints remain in force.

## Global constraints

- macOS 14 or later. No hosted AI or external runtime dependency.
- Listening starts only after the user presses Enable in this launch. It never auto-enables after restart, installation, or permission grant from a stale start request.
- Listening can continue with windows closed while the app remains running. Quit stops it. No login item or after-Quit helper.
- Microphone permission is explicit. Speech authorization is requested only for name recognition. Set requiresOnDeviceRecognition; do not fall back to server recognition when unsupported.
- No audio files, transcripts, or recognition logging. In-memory frames/results are discarded after detection. No sensitive actions or reminder mutations from audio activation.
- A persistent visible microphone/menu indicator and Stop Listening control are required. Sleep/session lock suspends listening; resumption requires explicit enable for this version.
- Edge feedback is brief, click-through, does not steal focus or capture screens, and respects Reduce Motion. Theme preferences are non-sensitive local settings.
- Development ad-hoc signing is not an App Store release. Do not overwrite another installed app or request permission during automated validation.

## Task 1: Detection and local audio adapter

Owned files: new activation files under Sources/ArgusCore and Sources/ArgusPlatform, corresponding test files only.

Interface: `ActivationMode` (clap, wakeWord, both), `ActivationTrigger` (clap, wakeWord), `AudioActivationState` (stopped, requestingPermission, listening(ActivationMode), unavailable(String)); main-actor `AudioActivationService` exposes state, onActivation and onStateChange callbacks, `start(mode:) async`, `stop()`. `LocalAudioActivationService` is the native implementation.

- [ ] Write tests for impulse versus sustained loudness, cooldown, exact wake-word token matching, repeated partials, and reset.
- [ ] Run real failing assertions before detector implementation.
- [ ] Implement bounded transient detection and token matching. Test with synthetic frames, not claims of physical microphone recognition.
- [ ] Implement permission-gated AVAudioEngine capture, local-only speech with supported-language availability checks, permission/start cancellation fencing, interruptions and complete stop teardown. Native errors must stop capture and show actionable status.
- [ ] Test start/stop races with injected boundaries and build actual native adapter under Swift 6. No live microphone during tests.
- [ ] Commit scoped changes and report on-device availability/physical detection limitations.

## Task 2: Theme and activation presentation

Owned files: new theme/controller/settings files under Sources/ArgusPresentation, TodayView.swift, SettingsView.swift, presentation tests. Root owns AppModel and app composition.

- [ ] Write tests for default green accent, persisted valid color, corrupted preference fallback, controller start/stop status and stale callbacks.
- [ ] Implement a shared `AppearanceSettings` with custom hex RGB/presets, non-sensitive UserDefaults storage, and SwiftUI Color conversion.
- [ ] Implement `ActivationController` around the service. Initialization never starts audio. User can choose mode, enable, stop, and preview the glow without microphone access. Surface state plainly and explain background-window versus Quit behavior.
- [ ] Expose settings in the sidebar Settings and a compact microphone state/control in Today. Preserve existing `TodayView(model:)` and `SettingsView(model:)` compatibility through optional injected controller/settings.
- [ ] Verify injected fake service never requests real permission; edit/restart preference tests; commit owned files.

## Task 3: Screen-edge feedback

Owned files: new Sources/ArgusPresentation/ScreenEdgeGlow.swift and dedicated tests if applicable.

- [ ] Define testable geometry/policy for brief bounded glow and reduced-motion handling.
- [ ] Implement main-actor AppKit controller with borderless non-key/non-main panels, ignoresMouseEvents, no activation, screen-change cleanup, and deterministic hide/stop.
- [ ] Public API: `ScreenEdgeGlowController.show(color: NSColor)`, `hide()`; no audio/permissions of its own.
- [ ] Test geometry/policy and compile. No native launch from worker. Root demonstrates preview in isolated app.

## Task 4: Composition, icon and install

Root-owned: Sources/ArgusApp/ArgusApp.swift, Package.swift if needed, Config/Info.plist, Resources assets, packaging scripts, docs.

- [ ] Wire one service/controller/theme/glow across app windows and menu-bar status. Add microphone/speech usage descriptions. Stop capture and hide overlays on termination, sleep and screen lock.
- [ ] Create an original green many-eyed icon, package complete macOS icon sizes, declare CFBundleIconFile, and verify resources before signing.
- [ ] Run full test and development bundle verification. Independent review must cover capture lifecycle, consent, local-only enforcement, overlay focus behavior and persistence.
- [ ] Demonstrate theme/preview/mute state with disposable data and no automatic microphone permission prompt. Live audio requires the user's Enable action and macOS approval; report if not tested.
- [ ] Install the verified bundle under ~/Applications/ARGUS.app only if absent. If present, inspect before replacing; do not delete or overwrite an unrelated app.
- [ ] Verify installed signature, resource existence and executable identity; open the installed app with listening disabled. Record local-only installation, external microphone/recognition and release-signing limits.
