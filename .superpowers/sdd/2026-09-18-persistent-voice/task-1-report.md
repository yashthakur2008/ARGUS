# Task 1: persistent voice lifecycle and offline speech

Status: Ready. Task 1 owned source frozen after scoped commit. No subagents spawned.

## Scope and exact public APIs

All APIs below are main-actor isolated unless they are Sendable enum values.

- `@Observable VoiceExperienceController.init(activation: ActivationController, speech: any SpeechOutput, defaults: UserDefaults = .standard, permissions: any ActivationPermissionChecking = NativeActivationPermissionChecker())`.
- Read-only `alwaysListen: Bool`, `spokenResponses: Bool`, `isSpeaking: Bool`, `statusText: String`, `preferredMode: ActivationMode?`.
- Async `setAlwaysListen(_ enabled: Bool)`, `enableOnce()`, `resume(reason: VoiceSuspensionReason)`, `restoreIfEnabled()`, `setMode(_ mode: ActivationMode)`.
- Synchronous `requestAlwaysListen(_ enabled: Bool)`, `requestEnableOnce()`, `requestResume(reason: VoiceSuspensionReason)`. UI/lifecycle callers should use these directly rather than wrapping async intent changes in an unguarded Task. Intent/reason mutation occurs immediately, and queued capture work is generation-fenced.
- Synchronous `setSpokenResponses(_ enabled: Bool)`, `stopListening()`, `suspend(reason: VoiceSuspensionReason)`, `handleActivation(_ trigger: ActivationTrigger)`, `previewSpeech()`.
- `VoiceSuspensionReason: Hashable, Sendable` cases `systemSleep`, `displaySleep`, `screenLock`, `sessionInactive`, `startupUnverified`.
- `SpeechOutput` protocol: `isSpeaking: Bool { get }`, mutable `onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?`, `@discardableResult speak(_ text: String) -> UUID`, `stop()`. Completion must occur after speak returns its ID.
- `SpeechOutputResult: Sendable, Equatable` cases `finished`, `cancelled`, `failed`.
- `NativeSpeechOutput.init()` does not instantiate AVSpeechSynthesizer until the first explicit speech request. Internal injectable driver factory supports silent adapter tests.
- `ActivationPermissionChecking.isAuthorized(for mode: ActivationMode) -> Bool`, implemented by `NativeActivationPermissionChecker.init()`. Queries existing AVFoundation/Speech authorization only.
- `ActivationController.enableIfAuthorized() async` preserves existing explicit `enable()` behavior.
- `AudioActivationService.startIfAuthorized(mode: ActivationMode) async` has a safe default that stops instead of falling back to a prompting start. `LocalAudioActivationService` overrides it with zero permission-request calls.
- `AudioActivationBackend.existingPermissionsAllow(mode: ActivationMode) -> Bool` defaults false. Native backend uses the noninteractive checker.

`VoicePreferences` is internal. Keys are `voice.alwaysListen`, `voice.spokenResponses`, `voice.activationMode`. Both persistent switches default OFF. Mode selection is persisted only through explicit `setMode`; initialization never overwrites current activation mode. Root deliberately applies optional `preferredMode` before first capture.

## Safety behavior

- Stop and always-listen OFF synchronously clear remembered listening intent, stop both resources and invalidate queued work/cooldowns/completions.
- Sleep, display sleep, lock and inactive-session suspension synchronously stop capture/speech while preserving remembered intent. Clearing a wake reason cannot clear a lock reason.
- Root owns seeding `startupUnverified`. Automatic restore never removes it. Explicit enable/one-shot removes only this unknown-startup reason, not known suspension reasons.
- Explicit test voice may play while only startup verification is pending, even without microphone permission. It does not remove the startup gate or authorize capture.
- Capture stops before speech. Normal completion resumes only the same current capture intent after a cancellable 200ms cooldown. Superseded, cancelled, failed, muted and mode-invalidated callbacks cannot restart it.
- Disabling speech independently restores valid paused persistent or one-shot capture through a new authorized-only, generation-fenced request. A later Stop/lock prevents that queued resume.
- Pending permission cleanup is serialized. A valid lifecycle resume waits for older cleanup instead of losing intent or permitting overlapping starts.
- Native synthesis uses installed English macOS voices, bounds text to 160 characters, and reports real delegate finish/cancel. A 30-second watchdog reports failure, never success. No speech text is logged. Coordinator only submits two fixed non-personal phrases.

## Verification and review

Toolchain: `/Users/yashthakur/.jcode/scratch/argus-swift-6.1.2/expanded/swift-6.1.2-RELEASE-osx-package.pkg/Payload/usr/bin/swift`.

Behavioral red evidence in scratch logs:
- `task1-red.log`: original coordinator scaffold compiled; 13 tests, 19 expectation issues.
- `task1-startup-red.log`: 15 coordinator tests, 20 issues.
- `task1-auto-red.log`: authorized-only service tests, 3 issues.
- `task1-tts-red.log`: silent native speech adapter tests, 8 issues, while coordinator/legacy tests were green.
- `task1-ui-red.log`: queued Enable/Stop and unlock/new-lock races, 5 issues.
- `task1-toggle-red.log`: independent speech-disable restoration and speaking status, 7 issues.
- `task1-status-red.log`: OFF startup status assertion failed before correction.

Final full Swift Testing command `swift test --disable-xctest --enable-swift-testing`: **256 tests passed**, including 31 Task 1 additions (25 coordinator, four silent native adapter, two authorized-only service). Plain `swift build` passed. Logs: `task1-final-tests.log`, `task1-final-build.log`. No warnings or errors in final logs. `git diff --check` passed.

Early builds collided with other owners editing inputs and were rerun after those edits settled. One full-suite run exposed that a test's 350ms wait could start before the cooldown Task was scheduled under main-actor load. Tests now first yield to queued work before waiting for the real cooldown. Final full suite passed.

Independent read-only reviewer cactus reported no remaining Task 1 blocker after inspecting callback fences, native synthesis and synchronous UI APIs. Root-owned app/lifecycle/settings wiring is not part of this scoped commit.

## Limits and remaining external gates

- No real microphone, permission dialog, playback, Keychain, network, login mutation, app launch, bundle, install or signing operation was performed.
- Actual installed-voice playback and physical capture are untested external gates. Native AVSpeechSynthesizer has no failure delegate, so failures without finish/cancel are detected by the bounded watchdog. Its 30-second wall-clock timeout was inspected, not waited out in tests.
- Local speech requires an installed English voice. If none exists the adapter fails closed without downloading one.
- Public APIs do not prove current lock state at launch. Root must establish startup/lifecycle suspension before automatic restore and clear unknown startup only through an observed unlock or explicit user action.
- Async intent APIs remain for structured callers and tests. UI must retain the synchronous request wrappers or an equivalent pre-enqueue generation fence.
- A synthesis error/cancellation leaves capture stopped until an explicit valid retry or later valid lifecycle restore. It never fabricates successful completion to restart capture.
