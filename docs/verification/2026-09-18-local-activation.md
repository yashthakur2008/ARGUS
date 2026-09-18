# Local activation and installation verification

## Scope and checkpoint

Verified September 18, 2026 UTC, against application commit `fae57f6`, including native audio commit `6962241`. This is an ad-hoc development build, not an App Store release.

Implemented opt-in clap/name activation, local-only US English speech recognition, bounded screen-edge feedback, persisted green/custom theme, original guardian icon, and native menu controls. Activation produces visual feedback only. No consequential command execution, hosted recognition fallback, stored audio, or transcript logging was introduced.

## Automated evidence

Root ran `ARGUS_SWIFT=<verified Swift 6.1.2 executable> bash scripts/verify.sh` after all workers froze their source. Background task `763179bhkh` exited 0 at 06:09 UTC. Swift Testing reported 190 tests passed; the two opt-in SQLite profiling tests remained skipped. Release compilation, icon generation, usage-description/resource checks, ad-hoc signature validation, and private-runtime-path checks passed.

Prior runs are not counted as successes: one caught a new interruption-observer regression during its red phase, and another passed tests but failed release compilation because a source file changed during the build. The final frozen-source run above passed both stages.

Tests cover synthetic transient detection, exact wake-word tokens, cooldown/reset, permission cancellation and stale callbacks, capture/speech epochs, local-only request flags, locale normalization, bounded speech renewal, unavailable-recognizer stop, synchronous suspension revocation, theme persistence, and passive overlay policies. Fake audio boundaries do not verify physical microphones or speech accuracy.

## Installed native checks

- Installed the verified bundle at `~/Applications/ARGUS.app`, after confirming no existing app at that destination. No unrelated installation was overwritten.
- Verified installed signature and executable byte equality with the release development bundle. Original `ARGUS.icns` is packaged.
- Ran the installed app with disposable data and a separate preferences suite. No microphone or Speech permission was requested.
- Preview produced exactly two ARGUS-owned layer-25 panels matching the two connected display bounds. The existing application window stayed at layer 0. The frontmost application remained Warp before and during preview.
- A subsequent owned-window enumeration showed both preview panels removed. The implementation's 1.2-second duration is covered by policy tests; this native check confirms eventual dismissal, not a precise timing measurement.
- Selected Lavender through native Settings. The hex field became `#AD9CE3`. After Quit/relaunch with the same isolated preferences, it remained `#AD9CE3` and status was `Microphone off`.
- Quit the isolated demonstration and opened the installed app normally, without fixture environment overrides. The running executable path is `~/Applications/ARGUS.app/Contents/MacOS/ARGUS`.

Only ARGUS-owned window metadata was inspected for overlay verification. The app itself does not capture screens. Live audio was deliberately left for the user's explicit Enable action.

## Remaining external verification

Physical clap detection, on-device recognition availability/accuracy, actual permission prompts and denials, and hardware interruption behavior remain unverified on this laptop. US English local resources may be unavailable; the implementation fails closed and offers an explicit clap-only selection. Sharp sounds may produce false positives. Test fake-boundary assertions do not substitute for these checks.

Actual notification delivery, signed sandbox confinement, Developer ID/App Store signing, archive validation, and App Store review remain separate gates. Listening is off each launch, stops on Quit/sleep/lock, and does not restart automatically. No login helper was installed.

## Publication status

Feature commits are local on `feat/reminders-slice`. GitHub `main` still contains the initial README, and the existing OAuth credential lacks the `workflow` scope required to publish the workflow change. No credential scope was changed and no force-push was attempted during this feature batch. Earlier user-requested date redistribution is backed up locally; publishing rewritten history requires a deliberate coordinated push, not an ordinary silent update.
