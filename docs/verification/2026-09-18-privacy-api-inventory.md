# Privacy API inventory, 2026-09-18

This is a source-review checklist for the commercial-release gate, not a privacy manifest, legal assessment, runtime network audit, or claim of App Store compliance. No credentials, microphone, speech service, login registration, notification permissions, or user database were accessed for this inventory.

## Observed API use

| Surface | Production source | Observed purpose and release review needed |
| --- | --- | --- |
| Preferences | `Sources/ArgusPresentation/VoicePreferences.swift`, `AppearanceSettings.swift`, `ElevenLabsSettingsModel.swift`; `Sources/ArgusApp/ArgusApp.swift` | `UserDefaults` stores explicit listening/speech choices, activation mode, appearance and ElevenLabs transmission consent. The app accepts an isolated preferences suite for development. Verify the current required-reason declaration for the actual distribution channel and final app identity. Do not classify the API key as a preference: its storage is separate. |
| Elapsed time | `Sources/ArgusPlatform/NativeAudioActivationSession.swift`, `NativeAudioCapture.swift`, `NativeSpeechRecognition.swift` | `ProcessInfo.processInfo.systemUptime` supplies local timing for activation samples, recognition events and session renewal. Include these three call sites in the current required-reason API review rather than auditing only preferences. No approved reason code was selected by this work. |
| Microphone | `Sources/ArgusPlatform/NativeAudioCapture.swift`, `NativeAudioActivation.swift` | Native permission and `AVAudioEngine` capture support clap/name activation. `Config/Info.plist` contains a microphone usage description. Validate permission denial/revocation and the shipped disclosure against actual behavior on hardware. Source inspection is not proof of all runtime retention behavior. |
| On-device recognition | `Sources/ArgusPlatform/NativeSpeechRecognition.swift` (including `NativeSpeechRequest`) | Recognition requires on-device support and uses an offline-required request. The usage description distinguishes recognition from server speech. Transcripts cross an ephemeral detector boundary in source. Confirm supported-language/resource failures without a hosted-recognition fallback in native acceptance. |
| Cloud voice output | `Sources/ArgusPlatform/URLSessionElevenLabsTransport.swift`, `ElevenLabsSpeechOutput.swift`; `Sources/ArgusPresentation/ElevenLabsSettingsView.swift` | Opt-in ElevenLabs HTTPS sends response text, not captured audio or recognition transcripts. An ephemeral session, bounded response handling and redirect rejection exist in source/tests. Provider retention, commercial terms, data disclosures, credits and audible acceptance remain separate gates. No live provider request was made for this inventory. |
| Credential storage | `Sources/ArgusPlatform/NativeElevenLabsKeychain.swift` | `SecItemCopyMatching`, add/update/delete operate on a fixed login-Keychain item with current-app access controls. This is a development implementation, not proof of Data Protection Keychain or broker-private isolation. Signed synthetic-secret access-denial testing remains required. |
| System notifications | `Sources/ArgusPlatform/UserNotificationClient.swift` | `UNUserNotificationCenter` is the OS scheduling/authorization boundary. Distinguish reminder content saved locally, pending requests and actual delivery in privacy/product materials. No actual notification was sent by this inventory. |
| Login item | `Sources/ArgusPlatform/LoginItemService.swift` | `SMAppService.mainApp` reports/registers/unregisters launch-at-login state through explicit controls. Review startup behavior under the chosen signed identity and distribution channel. Nothing was registered or unregistered by this inventory. |
| Local storage | `Sources/ArgusStore`, `Sources/ArgusApp/ArgusApp.swift` | Reminder/history/policy storage is plaintext SQLite under the app's selected local directory. A private directory is not encryption. Encryption, migration, backup/retention and deletion policies require their own reviewed design. |

## Manifest and packaging observations

At the inspected development checkpoint, no `PrivacyInfo.xcprivacy` existed under `Sources` or `Config`, and none was present in the built `build/ARGUS.app`. This is an observed inventory gap, not a determination of every channel's submission requirements.

The current development packager copies a known executable, icon and Info.plist into a fresh bundle. Adding a source manifest alone would not prove that a release artifact contains it. Once declarations are reviewed and authorized, packaging and verification must explicitly include and inspect the final manifest, alongside the chosen signing/entitlement configuration.

A narrow keyword scan found no source matches for the checked file-metadata/capacity API names. That does **not** establish absence of all required-reason APIs, indirect system/library use, dynamic behavior or future dependencies. The detailed local evidence lists exact patterns and matched source lines in `validation/task-013-api-inventory.json` within the overnight run.

## Required follow-through

1. Review current Apple documentation and the intended distribution channel. Map actual uses to permitted declarations rather than guessing reason codes.
2. Review bundled dependencies and the final archive, not only application source keywords.
3. Reconcile user-facing text, provider terms, privacy policy and any submission disclosures with observed data flows and retention.
4. Add only approved declarations, then test artifact inclusion and validate the selected release path with an authorized signing identity.
5. Retain the separate live-provider, hardware, signed-isolation and storage-security gates. This document does not close them.
