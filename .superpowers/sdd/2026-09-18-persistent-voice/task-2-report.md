# Task 2 report: login adapter and settings controls

## Scope and frozen API

Owned files only:
- `Sources/ArgusPlatform/LoginItemService.swift`
- `Sources/ArgusPresentation/LoginItemController.swift`
- `Sources/ArgusPresentation/VoiceSettingsView.swift`
- `Tests/ArgusPlatformTests/LoginItemServiceTests.swift`
- `Tests/ArgusPresentationTests/LoginItemControllerTests.swift`

Public API follows the plan:
- `LoginItemStatus`: `disabled`, `enabled`, `requiresApproval`, `unavailable`.
- `@MainActor LoginItemService`: `status`, throwing `setEnabled(_:)`.
- `NativeLoginItemService()` wraps `SMAppService.mainApp`. Initialization only inspects bundle configuration. Non-app execution reports unavailable. Native status is re-read, including after successful or failed mutations. Unknown/native-not-found statuses map to unavailable.
- `@MainActor @Observable LoginItemController(service:)`: read-only `status`, `isEnabled`, `isWorking`, `errorMessage`, computed `statusText`, `setEnabled(_:)`, `refresh()`.
- `VoiceSettingsView(voice: VoiceExperienceController, login: LoginItemController)`: two sections for root's existing Settings Form. Task1 owner confirmed the voice API before this view was written.

`isEnabled` means actual OS enabled, never saved intent or pending approval. Approval has explicit explanatory text and a cancel-registration action, not a misleading enabled switch. Errors remain visible through read-only refresh and clear after a successful explicit change. View appearance and scene activation only refresh status.

Always listen and spoken response bindings use the shared voice coordinator, with no duplicate persisted state. Always listen OFF and Stop call synchronous `stopListening()`. Test voice uses installed-voice preview and is disabled when spoken responses are off. Text explains independent microphone/login permissions, remembered consent, local speech, and Quit semantics.

## Tests and evidence

Used the plan's installed Swift 6.1.2 executable. No downloads.

1. Behavioral controller RED: six tests against an inert controller scaffold ran, with five failures and 20 assertion issues covering absent registration forwarding, absent initialization/status refresh, missing error propagation and approval text. Default-off test already passed the inert scaffold. An earlier attempt was invalidated by another owner's concurrent source edit, then rerun successfully to obtain this real behavioral red.
2. Controller GREEN plus mapping RED: all six controller tests passed. Pure ServiceManagement status mapping against an intentionally inert mapper failed three assertions for enabled/approval/unavailable.
3. Final focused GREEN: `swift test --disable-xctest --enable-swift-testing --filter LoginItem` passed all seven tests. Both the real native adapter and VoiceSettingsView compiled as part of this build.
4. Plain `swift build` passed with exit 0.
5. `git diff --check` passed.

Logs are in `/Users/yashthakur/.jcode/scratch/task2-red.log`, `task2-map-red.log`, `task2-green.log`, and `task2-build.log`.

Tests inject a fake LoginItemService. Native tests call only the pure status mapper. No test constructs SMAppService or invokes live registration/unregistration. Controller initialization, repeated refresh and external status transitions are covered, including preservation of an error while reflecting actual post-error status.

## Root integration and limits

Root constructs and retains one `LoginItemController(service: NativeLoginItemService())`, passes it plus the shared voice controller to the view, and owns App/Settings wiring. Keep explicit Start once in existing activation controls. Full cross-owner suite and integration review remain root's final gate. No unrelated files were changed.

Real macOS registration, approval, login relaunch and installed-app configuration behavior remain deliberately unexercised. No app launch, bundle/install, network, Keychain, microphone access, speech playback, permission prompt or live login mutation was performed. Native APIs are compile-verified only. SwiftUI controls are compile-verified, not interactively clicked.

Task 2 froze at commit `28fabd5`. Root subsequently authorized a narrow view/report follow-up after review found that the view's queued async enable could run after a synchronous Stop. The follow-up replaces that outer Task with Task1's synchronous `requestAlwaysListen(_:)` entry point, whose coordinator-owned generation fence handles deferred startup safely. Root also requested explicit cold-launch copy: ARGUS waits for an observed unlock or explicit Start listening and does not infer the initial lock state.

Follow-up validation: sabertooth confirmed the synchronous API ready and its queued-enable-after-Stop regression had behavioral red/green. The view now calls `voice.requestAlwaysListen($0)` directly with no outer Task. Ran `swift test --disable-xctest --enable-swift-testing --filter 'LoginItem|VoiceExperienceControllerTests'`: all 24 tests passed, including `queuedEnableCannotUndoLaterSynchronousStop` and `queuedResumeCannotClearNewerLock`. Plain `swift build` and `git diff --check` passed. Logs: `/Users/yashthakur/.jcode/scratch/task2-followup-green.log` and `task2-followup-build.log`. This follow-up edits only VoiceSettingsView and this report. Files are frozen again after the final follow-up report.
