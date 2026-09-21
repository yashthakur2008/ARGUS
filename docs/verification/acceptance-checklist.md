# ARGUS external acceptance checklist

Automated tests, fake-boundary regressions, stress repetitions, and ad-hoc development bundle checks are useful development evidence. They are not acceptance for live macOS behavior, provider behavior, distribution, or commercial readiness. Use this checklist before claiming any corresponding capability is ready for users.

## How to use this checklist

- Run acceptance on a clean build from the exact commit under review.
- Record the commit, macOS version, hardware class, display setup, signing identity or ad-hoc status, toolchain, and data directory used.
- Link each completed item to a dated evidence note under `docs/verification/` or to the relevant CI run/artifact.
- Mark an item **blocked** rather than inferring success from lower-level automated tests.
- Use disposable reminders, synthetic credentials, and test accounts unless the user explicitly authorizes live-provider or account actions.

## Required external gates

| Gate | Claim it supports | Minimum acceptance evidence | Current status |
| --- | --- | --- | --- |
| Notification permission and banners | Reminders can visibly alert the user through macOS | User-authorized notification permission flow, observed banner/list delivery for one-time and recurring reminders, denied-permission behavior, Focus behavior, restart/reboot recovery, and documentation of rolling-window limits | Open. Existing tests cover planning, persistence, and reconciliation with fake OS boundaries, not observed banner delivery. |
| Sleep, wake, lock, and restart lifecycle | Reminder and activation state behaves predictably across common Mac lifecycle events | Observed behavior across lock/unlock, sleep/wake, app relaunch, and system restart with due, overdue, snoozed, and recurring reminders | Open. Synthetic lifecycle and store recovery tests exist, but public README still treats runtime delivery as unverified. |
| Live microphone activation | Clap/name activation works on supported hardware with explicit controls | Real microphone sessions for clap, name, combined modes, permission denial/revocation, speech-resource unavailable state, Stop listening, Quit, and no automatic permission request | Open. Injected audio/permission tests exist. Physical clap/name recognition remains separate acceptance. |
| Launch at login | Opt-in launch registration and post-login behavior work without hidden helpers | Toggle enable/disable, OS approval or denial states, logout/login or reboot observation, no microphone start without explicit activation policy, and Quit semantics | Open. Mapping/controller tests exist, not native login acceptance. |
| Optional ElevenLabs speech | Consented text-to-speech works and fails safely | User-authorized test key, entitlement/voice availability check, known fixed text request, audible playback, cancellation, revocation, locked Keychain behavior, and provider-cost disclosure | Open. Fake transport/playback tests exist. No live provider acceptance or charge authorization is implied. |
| Keychain and secret boundaries | Credentials are stored and scoped as documented | Synthetic secret save/read/delete, locked/unavailable Keychain behavior, rebuild/access-control behavior, log review, and signed isolation tests before release-secret claims | Open. Development login-Keychain path is tested, but production broker-private storage is not implemented. |
| Sandbox, signing, notarization, and distribution | Build is suitable for a selected distribution channel | Clean archive, explicit entitlements, Developer ID or App Store signing as appropriate, notarization/export validation when applicable, runtime dependency audit, and install/update/rollback exercise | Open. Current checks cover an ad-hoc development bundle only. |
| UI accessibility and native interaction | Core flows are usable beyond model-level tests | VoiceOver labels/order, keyboard navigation, reduced motion, scaling, empty/error states, interrupted edits, multi-display glow, and basic manual reminder CRUD | Open. SwiftUI compilation and model tests are not accessibility acceptance. |
| Upgrade, backup, and recovery | Existing users can move safely between builds | Disposable old-version data fixtures, migration, rollback, backup/restore, corruption handling, and no destructive real-user-data migration without approval | Open. Store migration and corruption tests exist for fixtures, not complete user-upgrade acceptance. |
| Prompt-library and bounded-worker MVP | ARGUS is the complete intended assistant MVP | Versioned prompt library, search, variables, queued preparations, three bounded workers, Stop All, approval boundaries, persistence, and native end-to-end acceptance | Open. Reminder and activation prototype is implemented, but README still identifies these MVP workflows as unfinished. |

## Evidence boundaries

The following are valuable but insufficient by themselves for the external gates above:

- Swift unit/integration tests with fake notification, audio, network, Keychain, or clock boundaries.
- Repeated stress runs of the same automated suite.
- Synthetic packaging or verifier failure-injection tests.
- Ad-hoc development bundle signing and `otool` runtime-path checks.
- Documentation review without an observed native run.

When evidence is partial, keep the product language scoped to the verified layer. For example, say “scheduled in ARGUS and reconciled with a fake notification boundary” rather than “delivered by macOS,” unless the banner was actually observed and recorded.
