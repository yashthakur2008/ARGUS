# Reminder slice verification record

Date: 2026-09-17 (America/Los_Angeles)
Branch: feat/reminders-slice
Status: core verified, persistence/native interface in progress. This is not full-slice or App Store acceptance.

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

A separate read-only core reviewer is checking specification compliance and code quality. Review approval is not yet recorded here.

## Not yet established

- Real SQLite persistence and crash/reopen behavior.
- Native command-to-store/UI journeys, approval-gated deletion and notification reconciliation races.
- Actual OS banner delivery, permission behavior, Focus, sleep/wake, explicit Quit, or machine restart.
- Signed App Sandbox, XPC worker isolation, Keychain boundaries, app archive or App Store acceptance.
- Prompt library, multi-hand runtime, optional voice, calendar adapter, or complete global stop behavior.

No notification permission was requested by these tests, no personal reminders were created, and no network request is part of the core runtime.
