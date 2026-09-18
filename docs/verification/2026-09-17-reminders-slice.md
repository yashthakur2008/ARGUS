# Reminder slice verification record

Date: 2026-09-17 (America/Los_Angeles)
Branch: feat/reminders-slice
Status: native reminder prototype built and partially demonstrated. Review fixes and durable notice recovery remain in progress. This is not full-slice or App Store acceptance.

## Toolchain investigation and controlled repair

1. Installed Command Line Tools report Apple Swift 6.1.2 and SDK 15.5. Full Xcode was not found in the checked standard application locations.
2. A standalone scratch probe importing Foundation, SwiftUI and UserNotifications failed before ARGUS source was involved: duplicate SwiftBridging definitions in the old module.modulemap and newer bridging.modulemap under the CLT Swift include directory.
3. A compiler-local VFS overlay hiding only the obsolete map made the original probe compile and run with exit 0. No system file was edited. This proves those native frameworks can compile with a narrowly scoped development workaround; it does not prove app behavior.
4. Installed `swift test` independently aborted before manifest evaluation because swift-package expected an unavailable llbuild symbol. This is a separate inconsistent CLT installation, not an ARGUS test failure.
5. Downloaded the official 1,530,375,397-byte Swift 6.1.2 macOS package from https://download.swift.org/swift-6.1.2-release/xcode/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-osx.pkg into agent scratch. `pkgutil --check-signature` reported Developer ID Installer: Swift Open Source (V9AUD2URP3), trusted Apple notarization, and a trusted timestamp. Expanded it with pkgutil only. No installer script, system installation, global PATH, xcode-select change, credential or paid operation was performed.
6. Extracted SwiftPM 6.1.2 works and bundles the official Swift Testing library/macros. The core builds and tests with this complete isolated toolchain, with no VFS overlay required. XCTest is unavailable in the current CLT environment, so tests use Swift Testing.

Verified development executable on this laptop:

```text
/Users/yashthakur/.jcode/scratch/argus-swift-6.1.2/expanded/swift-6.1.2-RELEASE-osx-package.pkg/Payload/usr/bin/swift
```

This path is developer tooling only. ARGUS must not depend on Jcode or this scratch directory at runtime. A clean release build with the proper Xcode toolchain remains a release gate.

## Actual core verification

Coordinator independently ran at 2026-09-18T02:28:35Z through 02:28:40Z, from the real repository:

```sh
"$ARGUS_SWIFT" test --disable-xctest --enable-swift-testing
"$ARGUS_SWIFT" build
git diff --check
```

Here ARGUS_SWIFT denotes the exact verified executable above, not the broken system SwiftPM. Observed: **30 Swift Testing tests passed**, build passed, diff hygiene passed. No synthetic copy of the core was used. Tests call the production module with deterministic clocks and fixtures.

Coverage includes:
- Relative reminder parsing against injected time, singular/plural units, strict UUID selection, literal titles, explicit commands, invalid/unsupported grammar, ISO8601 offset/fraction retention and invalid calendar dates.
- Validating initialization and Codable round trips, invalid decode rejection, title/zone/revision/time/offset limits, duplicate-offset normalization, and finite-but-unrepresentable timestamps.
- One-time alert offsets, stable unique IDs, completion/empty offsets, bounded horizons, exact 64-notification boundary, limit failure, snooze without moving the deadline, weekday/weekend behavior, and advance alerts for deadlines beyond the immediate alert horizon.
- Cairo weekday DST gap/fold fixtures, avoiding the false reassurance of testing only US Sunday transitions for a weekday rule.
- Quiet hours crossing midnight, disabled interval, DST boundaries, explicit bypass, and one-time/recurring restart during quiet hours preserving a still-future deferred alert.

## Red/green evidence and limitations

The worker authored tests before initial implementation, but the broken compiler/SwiftPM prevented meaningful initial red execution. Therefore this work is **not claimed to have strict behavioral RED before every initial function**. After restoring a working isolated toolchain, actual test runs exposed invalid ISO-date normalization, invalid decoded records, duplicate offsets, quiet-hour restart loss, and unsupported date range. The worker observed failing regression assertions before fixing those defects, then reported green; the coordinator reran the final suite independently.

Independent read-only reviews reproduced two core defects, three store/reconciliation defects, and three presentation defects rather than merely accepting existing green tests. See the checkpoint below. Passing a suite does not establish absence of untested defects.

## Integrated checkpoint at 02:50 UTC

The coordinator independently ran `ARGUS_SWIFT=<verified executable> bash scripts/verify.sh` from the actual repository at 2026-09-18T02:50:36Z. Exit 0 after 12.3 seconds:

- **94 Swift Testing tests passed** against production modules, real temporary SQLite databases, and controlled protocol fakes for the external notification boundary.
- Release-mode ARGUS executable built, development `.app` bundled, both plist checks passed, ad-hoc signature passed `codesign --verify --deep --strict`.
- `otool` dependency and LC_RPATH checks found no private build-machine runtime dependencies or search paths. The final bundle's remaining LC_RPATH was `@loader_path`. An injected absolute toolchain testing-library rpath had been removed by the bundler before signing.
- Native artifact is arm64, macOS 14 deployment target, development bundle ID `org.argus.local.development`, no release team/sandbox proof. Successful execution on this host does not establish testing on macOS 14 or Intel.
- `scripts/verify.sh` did not launch, install, request permission, notarize, or publish anything.

This is a historical integration checkpoint, not a claim that subsequently added recovery stubs/tests are green. The recovery worker later observed 11 expected failing issues across four new test functions before implementing schema 2.

### Review findings and their disposition

| Finding | Evidence / disposition |
|---|---|
| Later-occurrence recurring snooze emitted both original and snoozed alerts | Reviewer reproduced against actual core. Regression fixed with persisted `snoozedOccurrenceAt`, commit `66bb561`. |
| Restart between DST-fold instants selected the forbidden second occurrence | Reviewer reproduced Cairo case. Canonical per-day first occurrence and regression in `66bb561`. |
| Supported `Asia/Kolkata` missing from Foundation's enumerated zone list | Actual Foundation probe and red regression. Structured supported IANA aliases accepted in `c9dbcdc`. |
| Known stale completed OS add survived when subsequent enumeration failed | Reviewer reproduced with real reconciler/fake OS. Immediate owned-ID compensation and regression in `a844d27`. |
| SQL LIKE underscore wildcard adopted foreign version-zero database | Real SQLite fixture. Literal prefix validation and rejection-byte-preservation regression in `a844d27`. |
| Malformed version-one schema allowed duplicate IDs/multirow optimistic updates | Real SQLite fixture. Required identity/schema validation and regression in `a844d27`. |
| Title-only editor save shifts recurring time after a DST gap | Reviewer reproduced parser-to-draft case. Assigned for regression/fix, not yet closed at this checkpoint. |
| Long recurring snooze hides an earlier unsnoozed occurrence from Today | Reviewer compared actual scheduler and presentation API. Assigned for regression/fix. |
| Newer refresh read failure strands the checking status | Reviewer reproduced overlapping refresh and corrupt real SQLite payload. Assigned for regression/fix. |

Coordinator separately reran **38 core tests and core-target build** after the core review fixes at 02:44 UTC. Commit `b7fe553` subsequently added shared occurrence provenance needed by notice recovery, and its tests are included in the 94-test checkpoint.

## Actual isolated native demonstration

At approximately 02:47–02:55 UTC, the coordinator launched the development `.app` through Launch Services with an explicit temporary `ARGUS_DATA_DIR` under agent scratch. No normal Application Support database was populated. The initial executable SHA-256 was `04f380d3543ed0482e3015e155d17c6d7623423c8f8b786e75d4dce20f3088b3`.

Observed through native Accessibility, an ARGUS-window-only screenshot, and read-only inspection of the same fixture SQLite database:

1. Empty Today opened with no fabricated reminders and explicit notifications-not-enabled status. OS authorization remained `notDetermined`. No Enable notifications control was pressed.
2. Actual keyboard submission of `Remind me to ARGUS synthetic smoke test in 20 minutes` persisted exactly one record. Database `dueAt - createdAt` was **1200.0 seconds**, revision 1. Background AX text-value assignment alone had not updated the SwiftUI binding, so that was not counted as successful command entry. The keyboard fallback checked ARGUS focus and restored prior focus.
3. Closing the window left the process running. Explicit Quit then ended the observed PID. Reopening the app with the same fixture directory displayed the saved reminder. The scoped screenshot showed the native Today layout and the actual retained record, not a mockup.
4. A background AX menu action snoozed the reminder. Revision became 2, while `dueAt - createdAt` remained **1200.0 seconds**. However, the ten-minute preset used a stale view reference time: `snoozedUntil - updatedAt` measured **577.25088596344 seconds**, not 600. This is a real native-test failure, assigned for a clock-advance regression and fresh-clock model fix before final acceptance.
5. The native Delete sheet displayed the exact synthetic title, irreversible consequence, and five-minute expiry. Choosing Keep preserved one record at revision 2. Opening a fresh confirmation and choosing Delete removed that fixture record. Read-only `PRAGMA integrity_check` returned `ok`.
6. The isolated demo app was explicitly quit afterward. No actual OS banner, permission change, personal reminder, login helper, or background service was created by this demonstration.

Native create/restart/snooze/delete paths were exercised. Native editor text-entry, VoiceOver, real notification delivery, sleep/reboot, and the not-yet-built notice/settings follow-up were not demonstrated. A raw `notDetermined` enum warning visible in Today was also flagged for conversational, nonduplicative wording.

## Not yet established

- Full process-crash injection and every failure/restart journey. Real SQLite reopen, transaction rollback/conflicts and async reconciliation races are covered, but not every OS crash window.
- Complete native editor/notice/quiet-hours journeys and closure of the presentation findings above.
- Actual OS banner delivery, permission/Focus behavior, sleep/wake, or machine restart. Window close and explicit Quit/relaunch were observed separately as described above.
- Signed App Sandbox, XPC worker isolation, Keychain boundaries, app archive or App Store acceptance.
- Prompt library, multi-hand runtime, optional voice, calendar adapter, or complete global stop behavior.

No notification permission was requested by these tests, no personal reminders were created, and no network request is part of the core runtime.
