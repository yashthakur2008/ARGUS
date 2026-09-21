# Changelog

Versions identify development updates, not notarized or App Store releases. The existing app baseline was 0.1.0/build 1. This log begins here; earlier changes remain in Git history and verification records, not reconstructed release notes.

## v0.1.3 - 2026-09-20

- Improve local verification failure output when SwiftPM aborts from a mismatched Command Line Tools Swift/llbuild installation. The script now points contributors to an explicit Xcode or standalone Swift executable through `ARGUS_SWIFT`, and synthetic verifier tests cover that failure path.
- Add an external acceptance checklist for live notification delivery, sleep/wake behavior, microphone activation, launch-at-login, ElevenLabs, Keychain, signing/distribution, accessibility, upgrade/recovery, and MVP-completion gates. Link it from the README and commercial-readiness record so automated evidence is not mistaken for native or release acceptance.

## v0.1.2 - 2026-09-19

- Correct two timing-sensitive speech-timeout tests exposed by the first hosted DevOps PR run. Await the real completion callback through a buffered, cancellable AsyncStream instead of assuming a separate two-second polling deadline survives MainActor congestion.
- Keep the actual production watchdog, cancellation implementation, all existing timeout/late-callback assertions, and live microphone feature unchanged. Add an explicit test time-limit cancellation policy and cleanup.
- Preserve the failed hosted run and document the controlled actor-contention red/green experiment in [the iteration record](docs/verification/2026-09-19-stress-iteration.md). Passing stress repetitions did not erase the separately failing verification job.

## v0.1.1 - 2026-09-19

- Add bounded repeated default-enabled suite testing in Debug and Release, with per-run logs, metadata, and summaries that CI attempts to retain after failures. Runner outages or job cancellation can prevent artifact upload.
- Add failure-injection tests for the stress runner; failures stop a repetition sequence rather than being retried until green.
- Add a documented feature-to-test map with explicit native-device and distribution acceptance limitations.
- Add version/changelog consistency checks and a PR base-version/build increment check. Future updates must describe their changes under a new version and increment the app build number.
- Preserve live microphone activation and its permission controls unchanged. Automated stress runs use existing injected audio/permission tests; they do not establish live microphone acceptance.

Validation results belong to the linked PR/CI run for the exact commit. This entry describes the change, not an assertion that an unrun check passed.
