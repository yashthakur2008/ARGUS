# Changelog

Versions identify development updates, not notarized or App Store releases. The existing app baseline was 0.1.0/build 1. This log begins here; earlier changes remain in Git history and verification records, not reconstructed release notes.

## v0.1.1 - 2026-09-19

- Add bounded repeated default-enabled suite testing in Debug and Release, with per-run logs, metadata, and summaries that CI attempts to retain after failures. Runner outages or job cancellation can prevent artifact upload.
- Add failure-injection tests for the stress runner; failures stop a repetition sequence rather than being retried until green.
- Add a documented feature-to-test map with explicit native-device and distribution acceptance limitations.
- Add version/changelog consistency checks and a PR base-version/build increment check. Future updates must describe their changes under a new version and increment the app build number.
- Preserve live microphone activation and its permission controls unchanged. Automated stress runs use existing injected audio/permission tests; they do not establish live microphone acceptance.

Validation results belong to the linked PR/CI run for the exact commit. This entry describes the change, not an assertion that an unrun check passed.
