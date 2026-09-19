# Contributing to ARGUS

ARGUS is a development prototype, not a distribution-ready release. Start with the [README](README.md) and [commercial readiness evidence](docs/verification/2026-09-18-commercial-readiness.md).

## Propose a bounded change

1. Check existing issues and pull requests before opening a new one. For bugs, include reproduction steps, expected versus observed behavior, and the relevant build/toolchain. Do not include secrets or private reminder content.
2. Branch from current `main`. Keep each PR focused on one coherent change and reference its issue, when applicable. Do not split empty or cosmetic changes merely to generate activity.
3. Reproduce defects before fixing them. Prefer regression tests using disposable databases and injected clocks, permissions, transports, and playback boundaries.
4. Commit with accurate authorship and dates, then open a PR rather than pushing implementation changes directly to `main`. Do not rewrite shared history without agreement.

## Validate

On macOS with a working Swift 6.1 toolchain and SDK:

```sh
# Optional if the selected system Swift toolchain is unsuitable:
# export ARGUS_SWIFT=/absolute/path/to/swift
bash scripts/test-packaging-paths.sh
bash scripts/verify.sh
```

The path matrix uses synthetic tools. The verifier runs packaging/verifier regressions, Swift tests, and a release-mode development build with ad-hoc signing and runtime-path checks. It does not install or launch the app. GitHub Actions runs these checks on `macos-15` with Xcode 16.4.

For a focused Swift test, use the selected toolchain directly, for example:

```sh
"${ARGUS_SWIFT:-swift}" test --disable-xctest --enable-swift-testing --filter ReminderDraftTests
```

Report exactly which commands ran and their outcomes. Use `--skip-build` only when the existing test binary matches the current sources. Documentation-only changes may use link/command inspection plus hosted checks instead of a duplicate local build. Measure performance before and after when making performance claims.

## Review and acceptance

- Describe the before/after behavior, regression evidence, touched boundaries, risks, and rollback approach. Mark untested behavior explicitly.
- Check stale async callbacks, revision/sequence fences, partial persistence failures, and error ownership when changing storage or lifecycle behavior.
- Keep real credentials, provider requests, microphone capture, notification permission prompts, installations, and user data migrations out of automated fixtures. Native or chargeable acceptance requires explicit authorization and a separate record.
- Passing fake-boundary tests or an ad-hoc build does not prove notification delivery, accessibility, sandbox isolation, notarization, or App Store eligibility.
- Label AI-assisted review and its scope. A separate agent's source inspection is not independent human approval, and reported tests are not independently rerun tests. A PR author cannot approve their own PR on GitHub. Seek a qualified human reviewer for security, migration, or release-boundary changes.
- Address review findings and require relevant checks before merging. This guide does not itself configure branch protection or enforce approval rules.
