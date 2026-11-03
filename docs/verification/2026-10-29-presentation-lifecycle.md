# Introduction and automatic-update lifecycle verification

Date: 2026-10-29. Development version: 0.1.19 (build 20).

## Reproduction and bounded fix

`IntroUpdateHostingTests` mounts the production `TodayView` in an unshown
`NSHostingView`/`NSWindow`, using a disposable real reminder store and injected
notification/fetch boundaries. The window is never ordered front. It does not
launch ARGUS, request permissions, contact GitHub or initialize native capture.

Before the fix, the hosted view began its real SwiftUI task, introduction replay
cancelled the fetch, and dismissal failed to start another check. The regression
failed specifically on the second-fetch assertion, not on hosting or cancellation
setup. `checkedForUpdates` had been consumed before the first request completed.

The view now consumes its once-only attempt only after a noncancelled result or
error, and checks the live intro model before publishing even if SwiftUI has not
yet replaced the task input. Automatic checking waits for an overlapping Settings-owned check. A
completed result or offline error is reused without a duplicate fetch. If that
owner was cancelled, an active waiting caller may make a fresh attempt. A
cancelled waiting caller cannot initiate another request and is released without
waiting for the owner fetch to finish.

## Requirement-to-check map

| Requirement | Check | Evidence boundary |
| --- | --- | --- |
| Retry after intro interrupts a request | `IntroUpdateHostingTests.interruptedIntroCheckCanRunAfterDismissal`, ordinary, rapid dismissal and live-intro-before-view-update cases | Actual production view and SwiftUI task lifecycle, hidden window; not visible sheet acceptance |
| Do not consume a busy Settings check as completion | `AutomaticUpdateCheckTests.pendingSettingsResultIsSharedWithoutAnotherFetch`, success/offline cases | Production update model with controlled fetch continuation |
| Retry when request owner was cancelled | `activeWaiterRetriesAfterOwnerCancellation` | Production coordination and cancellation |
| Do not retry from a cancelled waiter | `cancelledWaiterDoesNotStartAnotherFetch` | Production coordination and cancellation |
| Release a cancelled waiter promptly | `cancelledWaiterFinishesWhileOwnerIsStillSuspended` | Failing regression reproduced before cancellation-aware continuation removal |
| Preserve freshness guarantees | Existing `GitHubUpdateFreshnessTests` | Failure, retry and late cancelled responses |
| Detect regression in busy behavior | Temporarily replacing the new waiting path with the former direct `check()` behavior makes overlap regressions fail; production source restored afterward | Mutation check, supplementary to the original hosted red regression |

The three-second hosted condition deadlines are failure watchdogs. Test ordering
uses observable state transitions and fetch continuations rather than sleeps to
pretend a request has completed. The rapid hosted variant orders wrapper-state
changes but does not expose the view task queue; direct model tests separately
exercise the pending-waiter interleaving. Hosted tests also await the successful
second result and permanently close their gate during cleanup.

## Native acceptance is not established

Accessibility and screen-observation permissions were available, but no ARGUS
process was running and no disposable native account/session was established.
Normal startup initializes the user's bundle-scoped notification center and can
restore remembered voice intent. A second data/preferences namespace alone does
not isolate those boundaries. No native ARGUS app was launched and no installed
bundle or user preferences were changed.

Accordingly, these remain deferred, not passed:

- Actual introduction sheet visibility from sidebar Settings.
- Standalone Settings replay with the main window closed. The main scene owns the
  sheet; standalone Settings has no sheet host or main-window opener in the
  current source. This limitation is not fixed by the update lifecycle change.
- Visible sheet/alert ordering, including replay after an alert is already shown.
- Green/lavender light/dark and reduced-motion visual acceptance.
- Alert payload changes during a subsequent manual Settings refresh.

Use an authorized disposable native session to exercise these workflows before
claiming end-user acceptance. This change does not add another sheet host, rewrite
presentation architecture, alter theme design or change update ancestry semantics.

## Reproduce automated checks

```sh
swift test --jobs 2 --no-parallel --disable-xctest --enable-swift-testing \
  --filter 'IntroUpdateHostingTests|AutomaticUpdateCheckTests|GitHubUpdateFreshnessTests'
bash scripts/verify.sh
ARGUS_PACKAGED_APP="$PWD/build/ARGUS.app" ARGUS_EXPECTED_COMMIT="$(git rev-parse HEAD)" \
  swift test --jobs 2 --no-parallel --disable-xctest --enable-swift-testing
```

The final command enables the existing real-bundle identity integration. Packaging
checks cover an ad-hoc development build, not release signing, notification delivery,
sandbox confinement or App Store acceptance.

## Observed automated results

Nine focused test functions passed, including the three hosted timing cases.
The complete verifier passed 451 test functions, with three opt-in functions
skipped: packaged identity and two SQLite profiling checks. It also built and
verified the actual development bundle. The packaged identity check is enabled
separately by the final command above; opt-in profiling is not claimed.

Independent read-only review found no blocking issue after the cancellation
retention and hosted cleanup corrections. Visible native presentation remains
unverified regardless of these automated results.
