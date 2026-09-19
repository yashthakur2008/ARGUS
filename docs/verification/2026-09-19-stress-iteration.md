# DevOps validation exposed a timing-sensitive test, 2026-09-19

## First hosted v0.1.1 attempt

PR [#6](https://github.com/yashthakur2008/ARGUS/pull/6), commit `96f96cb`, produced mixed evidence:

- [Stress workflow 35421432541](https://github.com/yashthakur2008/ARGUS/actions/runs/35421432541) passed three Debug and three Release repetitions. Both uploaded artifacts were downloaded and inspected: each contains three logs reporting 365 tests passed, successful summaries, app version 0.1.1/build 2, and clean PR merge checkout `87980f605db1b9bddec3d75caf1d5fa34d2326b5`.
- [Standard PR verification 35421432488](https://github.com/yashthakur2008/ARGUS/actions/runs/35421432488) failed six assertions across `timeoutCancelsAndNeverReportsSuccess` and `playbackTimeoutStopsAudioAndIgnoresLateFinish`. The expected timeout/cancellation callbacks had not arrived when the assertions executed. This failure was not retried away or treated as green because other jobs passed.

## Investigation and bounded correction

Both tests set a two-second wall-clock polling deadline immediately after `speak`. The production watchdog is an asynchronous MainActor task. Under actor congestion, the tests' polling deadline can expire before the watchdog gets enough scheduled turns to publish its result. A clock threshold in the test was therefore being used as an unreliable completion oracle.

To challenge this explanation, a temporary, explicitly synthetic test probe blocked MainActor for 2.1 seconds after deadline creation and before polling. The two tests reproduced seven failed assertions in the same categories (missing timeout, uncancelled request, and late success). This is a controlled scheduling probe, not an observed real-device audio defect. Exact source bytes were restored after execution.

The v0.1.2 test-only correction buffers the real `onCompletion` callback in AsyncStream and awaits it. It does not replace or inject the production timer. All timeout classification, request cancellation, playback stopping, and late-callback assertions remain. A one-minute Swift Testing time limit requests cancellation, which the stream iterator can observe, and deferred cleanup stops output. The CI job timeout remains the outer bound; neither limit is a product latency guarantee.

Repeating the same temporary 2.1-second actor-block probe before awaiting the callback passed both corrected tests. The focused 12-test speech suite also passed. The temporary blocking code was removed and the exact final source restored before subsequent validation. No production Swift source changed, and no live microphone or provider request was used.

## Evidence interpretation

The failed run and the corrective commit form the review trail. The DevOps runner itself did not fail or conceal the failure. Six passing repetitions did not prove an absence of timing-sensitive tests; a separate job exposed one. Subsequent checks on the updated PR must be read at their own commit SHA, not inferred from these earlier results. Local probe logs are retained in the agent scratch evidence directory; hosted failures and artifacts are linked above. No missing historical results are reconstructed.
