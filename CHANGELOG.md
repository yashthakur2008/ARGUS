# Changelog

Versions identify development updates, not notarized or App Store releases. The existing app baseline was 0.1.0/build 1. This log begins here; earlier changes remain in Git history and verification records, not reconstructed release notes.

## v0.1.15 - 2026-10-22

- Correct the reminder title limit shown on rejection. The message named 200 characters while 512 was enforced, so a valid title could be described as too long. The limit is now a single named value used by both the rule and the message.

## v0.1.14 - 2026-10-22

- Accept everyday command phrasing. `in 20 mins`, `in 2 hrs`, repeated spaces, and a trailing `.` or `!` previously failed as unrecognized commands even though the intent was unambiguous.
- Add one-time clock times: `remind me to Call mom at 09:00` and `remind me to Call mom tomorrow at 09:00`. A time that already passed today resolves to the next day rather than the past, and daylight-saving gaps resolve to a real local instant.
- Keep the grammar finite. Free text, spelled-out numbers, and empty titles are still rejected, and command words inside a title stay part of the title.
- Verify every example shown in the app actually parses, so guidance cannot advertise a phrase the parser rejects.

## v0.1.13 - 2026-10-21

- Replace raw Swift error text in user-facing messages. Failures previously showed internal case names such as `unsupportedCommand` or `sqlite(code:message:)`; each failure now states what was wrong and what to do instead.
- Check for updates against the branch development actually lands on. A current build previously reported "Update available" permanently and linked a commit older than the one it was built from.
- Move the Settings Privacy & Security pane mapping into the model and cover destination correctness and uniqueness, so a row cannot silently open an unrelated permission list.

## v0.1.12 - 2026-10-01

- Add a persistent Settings update status summary so ARGUS clearly says whether this Mac is current, has a new build available, cannot check GitHub, or is missing bundled commit metadata.
- Add regression coverage for user-facing update summary labels across current, stale, missing-metadata, and offline states.

## v0.1.11 - 2026-09-30

- Make the automatic GitHub update prompt less noisy: choosing Not now now defers the same latest commit for 24 hours, while a newer GitHub commit still prompts immediately.
- Add regression coverage for same-commit deferral and new-commit re-prompt behavior.

## v0.1.10 - 2026-09-26

- Add a GitHub-backed update check that compares the app bundle's embedded commit with the latest PR branch commit and shows an update prompt when a newer ARGUS build is available.
- Add Settings controls to check GitHub, view the latest commit or PR, and copy the rebuild command instead of silently leaving users on an old local app bundle.

## v0.1.9 - 2026-09-25

- Add a Settings permissions checklist with direct request buttons for notification, microphone, Speech Recognition, and Accessibility listing prompts, plus matching System Settings shortcuts.
- Make missing bundled changelog resources actionable so a stale running app clearly points users to rebuild or reinstall the latest ARGUS app bundle.

## v0.1.8 - 2026-09-21

- Add a Settings "What's new" section that shows the app version, build number, bundled Git commit, latest changelog notes, and a copyable diagnostic summary so users can confirm which ARGUS build is running.
- Bundle `CHANGELOG.md` and the current commit into each development app build, with synthetic packaging coverage that verifies those resources are present before publication.

## v0.1.7 - 2026-09-20

- Add actionable Settings issues for microphone/Speech permission problems and ElevenLabs setup gaps, including prominent banners, a popup details path, and sidebar surfacing when voice setup needs attention.
- Make ElevenLabs voice setup clearer by distinguishing missing API key, missing text-transmission consent, Keychain errors, and provider speech failures without adding a system-voice fallback.
- Add presentation tests for denied automatic voice restore and ElevenLabs missing-key/consent guidance. Local Swift execution remains subject to the documented toolchain requirement.

## v0.1.6 - 2026-09-20

- Add a fast repository hygiene check that requires no Swift compilation. It validates version/changelog consistency, Python syntax, shell syntax, trailing whitespace, and relative Markdown links, then runs from local and hosted verification before heavier Swift build steps.

## v0.1.5 - 2026-09-20

- Add a native notification acceptance procedure for user-authorized manual verification of macOS permission prompts, banner/list observations, denied-permission handling, Focus behavior, sleep/wake, restart, and recurring-window limitations. Link it from the external acceptance checklist.

## v0.1.4 - 2026-09-20

- Add focused refresh-publication coverage for public recovery mutations. Dismissed notices and policy edits now have regression coverage proving their follow-up refresh wins over an older in-flight load and preserves coherent reminders, notices, policy, status, and message state.

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
