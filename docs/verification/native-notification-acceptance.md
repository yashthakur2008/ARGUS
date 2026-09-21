# Native notification acceptance procedure

This procedure is for user-authorized manual evidence of macOS notification behavior. It complements automated reconciliation tests; it does not replace them and should not be run against important user data.

## Preconditions

- Build from the exact commit under review and record the commit SHA.
- Use an isolated data directory, for example `ARGUS_DATA_DIR` pointing at a disposable folder.
- Use a non-critical test reminder title and a Mac where notification banners can be observed.
- Record macOS version, Focus status, notification permission state before the run, display count, signing mode, and whether the app was launched from Finder, Terminal, or login.
- Do not claim App Store, notarization, or critical-alert behavior from this procedure.

## Permission and banner checks

1. Start with ARGUS notification permission unset if feasible on the test machine, or record the existing state if reset is not appropriate.
2. Create a reminder due in two to five minutes.
3. Use the explicit notification enable flow. Record whether macOS prompts, grants, denies, or routes to Settings.
4. If granted, wait for the due time and record whether a banner, Notification Center entry, sound, or no visible alert occurred.
5. Reopen ARGUS and confirm the in-app due or recovered notice state. This verifies app state observation, not proof of every macOS delivery path.

## Denied permission behavior

1. Deny notifications in System Settings or leave permission denied.
2. Create another short-delay reminder.
3. Confirm ARGUS keeps the reminder locally and reports notification permission denial rather than claiming delivery.
4. Confirm no destructive cleanup of reminder data occurs.

## Focus and notification settings behavior

1. Enable a Focus mode or notification setting that suppresses banners.
2. Create a short-delay reminder while permission remains otherwise authorized.
3. Record whether a banner is suppressed, delayed, or delivered silently according to macOS settings.
4. Confirm ARGUS does not claim Focus bypass, critical-alert delivery, or hard-real-time reliability.

## Restart, sleep, and recurring-window checks

1. Create one short-delay one-time reminder and one recurring reminder within the rolling scheduling window.
2. Quit and relaunch ARGUS before the due time. Record pending/scheduled status after relaunch.
3. Repeat with a sleep/wake interval crossing the due time if safe for the test machine.
4. Restart the Mac only with explicit user approval. After login, record which system notifications were observed and what ARGUS shows in-app.
5. For recurring reminders, record the next scheduled occurrence and note that the rolling window is a limitation, not a lifetime guarantee.

## Evidence record template

```text
Commit:
ARGUS version/build:
macOS version and hardware:
Signing/distribution mode:
Data directory:
Initial notification permission:
Focus/notification settings:
Scenario(s):
Observed macOS banner/list/sound behavior:
Observed ARGUS in-app state:
Logs/screenshots retained:
Limitations or blocked steps:
Conclusion scoped to observed behavior:
```

Use the conclusion to update the [external acceptance checklist](acceptance-checklist.md). If any step is blocked or ambiguous, keep the corresponding checklist gate open.
