# Repeatable stress evidence

The **Stress evidence** workflow runs the default-enabled automated Swift suite three times in Debug and three times in Release. Each configuration runs on a fresh hosted macOS job. The first repetition builds that configuration; later repetitions reuse its test binary. Opt-in SQLite profiling (`ARGUS_SQLITE_PROFILE=1`) is not enabled by CI. These are repeated executions of existing tests, not new unique tests, random fuzzing, or a long-duration hardware soak.

## Inspect the evidence

Open a pull request's **Repeated suite** checks, then the Actions run. Inspect the job summary and download the `stress-debug-...` and `stress-release-...` artifacts (GitHub login required). Artifacts expire after 14 days; the Actions run links and Git history retain the review trail subject to GitHub retention.

Each result directory contains commit/toolchain/configuration metadata, individual `run-N.log` files including stdout and stderr, and `summary.md`. A failing repetition stops that configuration, preserves the failed log, and fails the job. The other configuration still runs. No automatic retry-to-green is used. Summaries and uploads are attempted after failures; cancellation or a runner outage can prevent upload, so missing or partial evidence is not a pass.

PR runs test GitHub's merge checkout. Use the recorded checkout SHA rather than assuming it is the source branch's head. The workflow is also manually dispatchable once present on the default branch. It has no timer schedule, deployment step, provider credentials, or automatic merge. Jobs are capped at 20 minutes each and the two configurations are serialized.

## Reproduce locally

Requires the same working Swift/macOS SDK setup as the [README](../../README.md), plus Python 3 for automation checks. No third-party Python package is required.

```sh
# Optional: export ARGUS_SWIFT=/absolute/path/to/working/swift
python3 scripts/test-stress-test.py
python3 scripts/test-version-check.py
python3 scripts/check-version.py
output_parent="$(mktemp -d "${TMPDIR:-/tmp}/argus-stress.XXXXXX")"
bash scripts/stress-test.sh "$output_parent/debug"
ARGUS_STRESS_CONFIGURATION=release bash scripts/stress-test.sh "$output_parent/release"
```

Output directories must not already exist, to prevent overwriting earlier evidence. `ARGUS_STRESS_RUNS` may be set to an integer from 1 to 5; CI fixes it at 3. Local commands do not inherit the CI job timeout, so supervise them and retain incomplete evidence if interrupted. Do not run multiple local builds against the same `.build` directory concurrently. The runner's own failure-injection tests use fake Swift executables, not the real suite; their success is separate evidence about automation correctness.

## Feature-to-test map

This maps existing tests to risk areas, not a numerical coverage percentage or proof of all possible interactions.

| Area | Existing test files / suites | Boundary exercised and limits |
| --- | --- | --- |
| SQLite startup and recovery | `StoreMigrationTests`, `ActiveSnoozeConflictTests` | Concurrent opens/writers, migration preservation, bounded lock waits and occurrence conflicts with disposable SQLite databases. Not user-data upgrade acceptance. |
| Refresh and save overlap | `RefreshPublicationTests`, `DraftSavePublicationTests`, `RefreshResponsivenessTests`, `DraftSaveResponsivenessTests` | Delayed results, mutation fences, coalescing, partial errors and heartbeat regressions. Does not make every storage route nonblocking. |
| Notification reconciliation and editor actions | `ReconciliationOrderingIntegrationTests`, `PolicyAwareSnoozeTests`, `EditorSubmissionWindowTests` | Real model/store logic with fake OS boundaries, clocks, busy submissions and commit/read distinction. Not actual banner or Focus verification. |
| Time zones and recurrence | `CrossZoneScheduleInvariantTests`, `ScheduleCalculatorTests`, `QuietHoursTests` | Selected gaps/folds, exact anchors and restart-plan equivalence. Not an exhaustive proof for every time-zone database version. |
| Live microphone activation feature | `ActivationControllerTests`, `VoiceLifecycleIntegrationTests`, `AppLifecycleTests` | Injected capture/permission services exercise startup, lock/wake, stop and stale callbacks. **Live microphone support remains in the product.** CI does not open a microphone or prove real-device behavior. |
| Optional speech output | `ElevenLabsVoiceIntegrationTests`, `ElevenLabsTransportTests`, `ElevenLabsSpeechOutputTests` | Consent/key changes, cancellation, late callbacks and synthetic transport/playback. No real key, provider request, charge or audible acceptance. |
| Packaging | Standard `Verify macOS` workflow: `test-build-dev-app.sh`, `test-verify.sh`, `test-packaging-paths.sh` | Failure injection, previous-bundle preservation, path portability, plus actual development signing checks. The stress workflow complements, not replaces, these checks. |

Live microphone testing remains a separate, user-authorized acceptance task under [issue #2](https://github.com/yashthakur2008/ARGUS/issues/2). Preserve permission controls and explicit Start/Stop behavior. Do not silently enable capture or mistake mock evidence for native validation.

## Versioned updates

Every published update should have a `vMAJOR.MINOR.PATCH` entry at the top of [CHANGELOG.md](../../CHANGELOG.md) describing what changed. Increment both `CFBundleShortVersionString` and the integer `CFBundleVersion` in `Config/Info.plist`. Use the version in the update's commit/PR title. Patch versions cover compatible fixes and DevOps/docs updates; larger product changes should deliberately choose the appropriate minor/major version.

The workflow checks that the newest entry matches the app version and contains change notes. On PRs it also requires both version and build number to exceed the base commit. This validates each PR update against its base; it does not enforce a separate version on every intermediate local commit, validate the truth of prose, or create a release tag. Review the actual diff and evidence. Branch protection is not configured by this change, so repository owners can still bypass checks. Do not backdate entries or fabricate historical releases.
