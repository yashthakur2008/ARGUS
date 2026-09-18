# Task 3 report: bounded voice visuals

Status: READY, implementation frozen after final report. Root owns integration and final native review.

Implementation commit: `8e7fd78` (`feat: add bounded emerald voice feedback and motion override`). Only six owned visual/settings/test paths are included.

## Exact public API

```swift
VoiceStatusOrb(state: VoiceStatusOrb.State, accent: SwiftUI.Color, reduceMotion: Bool = false)
// VoiceStatusOrb.State: .off, .listening, .speaking
// State.label: "Voice off", "Listening", "Speaking"

@MainActor ScreenEdgeGlowController()
show(color: NSColor) // preserved, uses last configured override
show(color: NSColor, reduceMotion: Bool)
setReduceMotion(_ value: Bool) // updates visible overlays without replay or lifetime extension
hide() // preserved

@MainActor AppearanceSettings
public private(set) var reduceMotion: Bool
setReduceMotion(_ value: Bool)
public static let reduceMotionPreferenceKey = "argus.appearance.reduceMotion"
```

Override defaults false and persists independently of accent. Root passes `appearance.reduceMotion` to orb and glow, and calls `glow.setReduceMotion` when the override changes during display. Native system Reduce Motion always dominates: glow observes workspace accessibility-display changes, orb uses the SwiftUI accessibilityReduceMotion environment. Do not derive listening from remembered opt-in alone. Root should map actual speaking first, actual active listening second, otherwise off.

## Implementation

- Accent-derived highlight/base/deep gradient, rounded thin edge and soft inward halo. Default existing emerald accent is unchanged.
- One explicit opacity pulse of 0.9 seconds, zero repeats, removed on completion. Overlay expires at existing 1.2 seconds. No idle timer, display link, renderer, fake audio amplitude, or repeating animation.
- Motion enablement changes remove active pulse immediately. Turning reduction back off does not replay an old pulse or extend display.
- Orb is a compact 30-point gradient sphere with actual status icon and visible/accessibility label. Only finite 0.18-second state transitions. Motion policy changes replace its subtree to cancel in-flight transitions.
- Original nonactivating, never-key/main, clickthrough, status-bar level, all-spaces/fullscreen auxiliary policy retained. Display iteration, cancellation epoch, screen-change hide, expiry, and resource cleanup preserved. Added native notification observer is removed during disposal.

## Tests and evidence

Used preinstalled Swift 6.1.2, no downloads or toolchain changes:

```sh
/Users/yashthakur/.jcode/scratch/argus-swift-6.1.2/expanded/swift-6.1.2-RELEASE-osx-package.pkg/Payload/usr/bin/swift test --disable-xctest --enable-swift-testing --filter 'ScreenEdgeGlow|VoiceStatusOrb|AppearanceSettings'
/Users/yashthakur/.jcode/scratch/argus-swift-6.1.2/expanded/swift-6.1.2-RELEASE-osx-package.pkg/Payload/usr/bin/swift test --disable-xctest --enable-swift-testing
/Users/yashthakur/.jcode/scratch/argus-swift-6.1.2/expanded/swift-6.1.2-RELEASE-osx-package.pkg/Payload/usr/bin/swift build
```

- Actual behavioral RED: inert seams allowed tests to compile. 13 tests ran, 9 assertion issues for absent finite pulse, persisted override and honest labels. Log: `/Users/yashthakur/.jcode/scratch/task3-red.log`.
- Focused GREEN and fresh final GREEN: 13/13 tests pass. Real offscreen NSView/CALayer checks cover finite animation, zero repeat count, removal by either preference and no replay. Existing policy/geometry/epoch tests remain green. Persistence uses isolated defaults suites. Log: `/Users/yashthakur/.jcode/scratch/task3-focused-final.log`.
- Plain `swift build` passes. Log: `/Users/yashthakur/.jcode/scratch/task3-build.log`.
- Full test suite attempted twice. Initial attempt blocked by root's in-progress VoiceLifecycleBridge compile seam. Final attempt ran 241 tests with 29 issues, all outside Task 3: AuthorizedOnlyActivationTests (3), VoiceLifecycleBridgeTests (6), VoiceExperienceControllerTests (20). These were concurrent workers' test-first work in progress, not edited by Task 3. Root must rerun the full suite after integration. Log: `/Users/yashthakur/.jcode/scratch/task3-full-final.log`.
- Scoped `git diff --check` passed. Reviewed native focus/clickthrough/duration and teardown preservation in source.

## Constraints and limits

No native panel/app launch, audio, permission request, login registration, install, bundle, network operation, or subagent spawn was performed. Tests construct offscreen views and inspect their layers, never call glow.show. Actual rendered multi-display appearance, live OS accessibility notification delivery and SwiftUI transition cancellation were not visually exercised by this worker under the no-launch constraint. Orb tests cover honest labels and construction, not pixel output. Root retains native preview/review and full integration verification ownership.
