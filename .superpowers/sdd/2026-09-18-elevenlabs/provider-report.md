# ElevenLabs speech provider report

## Scope and integration API

Added only three platform implementation files and two provider test files. Existing `SpeechOutput`, `NativeSpeechOutput`, voice controller, UI and composition were not edited.

```swift
@MainActor protocol ElevenLabsCredentialProvider: AnyObject {
  func apiKey() throws -> String?
}

let output = ElevenLabsSpeechOutput(
  credentials: credentialProvider,
  disclosureAccepted: { /* explicit cloud-transmission consent */ }
)
```

The initializer also accepts `ElevenLabsSpeechTransport`, `MP3Playback`, and a watchdog `Duration` (default and maximum 30 seconds). All boundaries are public and replaceable. `onCompletion` preserves the existing `(UUID, SpeechOutputResult)` contract and always runs after `speak` returns. `onFailure(UUID, ElevenLabsSpeechFailure)` supplies a redacted typed reason in the same deferred delivery, before `.failed` completion. `lastFailure` exposes the most recent request failure.

Setup failures are `.disclosureRequired` and `.credentialRequired`. Missing, inaccessible, empty or malformed keys fail closed. No fallback to a system voice occurs. Callers should correlate callback UUIDs and should stop the output when withdrawing consent. Consent is checked on each explicit `speak`, not automatically observed during an in-flight request.

## Request and safety behavior

- Fixed voice: `ysswSXp8U9dFpzPJqFje`.
- HTTPS POST to `api.elevenlabs.io/v1/text-to-speech/{voiceID}?output_format=mp3_44100_128`.
- `xi-api-key`, JSON content type, MPEG audio accept header.
- `eleven_multilingual_v2`, stability 0.5, similarity boost 0.75, style 0, speaker boost enabled.
- Trimmed text capped at 160 characters, consistent with existing native output safety.
- No automatic access to transcripts, reminders, microphone or app data. Only explicit `speak` arguments are transmitted after disclosure/key checks.
- Request timeout 20 seconds, resource timeout 25 seconds, whole request/playback watchdog at most 30 seconds. Timeouts fail, never report successful completion.
- Ephemeral URLSession, no cookie/credential/cache storage, no response caching, no redirects (including same-origin redirects), endpoint allowlist, no retries.
- Status and MIME validated before body accumulation, 1 MiB incremental audio cap and provider-boundary recheck. Error bodies, underlying errors, keys and text never enter typed failures or logs.
- Native MP3 playback is in memory using AVAudioPlayer and real delegate completion. No temporary audio files.
- Cancellation and supersession invalidate request IDs before stopping transport/playback, so late/duplicate callbacks cannot revive or finish a new request.

API documentation verified via `webfetch` of https://elevenlabs.io/docs/api-reference/text-to-speech/convert on 2026-09-18. The docs note that provider zero-retention mode is enterprise-only. This implementation does not claim provider-side zero retention or set that enterprise-only option.

## Validation

Initial test-first run failed because the new provider/transport symbols did not exist. After implementation, the initial 11 provider tests passed with Swift 6.1.2. Expanded tests cover request construction, disclosure/key gating, malformed credentials, deferred and exactly-once completion, real-playback completion requirement, network/playback timeout, cancellation, stale/duplicate callbacks, byte bounds, status redaction, endpoint restrictions, redirect rejection and URLSession delegate flow using an all-URL-intercepting URLProtocol fixture.

Final verification with the supplied absolute Swift 6.1.2 binary:

- `swift test --filter 'ElevenLabs(SpeechOutput|Transport)Tests'`: **19 tests passed**.
- `swift test`: **293 tests passed**, including concurrently added credential/settings tests. Existing opt-in SQLite profiling tests remained skipped.
- `swift build`: passed without warnings.
- `git diff --check`: passed.

The first full run exposed two test-only fixed-40-ms scheduling assumptions under the loaded main actor. Replaced these with bounded condition-based waits for completion, then re-ran the full suite and focused suite successfully. No production timeout behavior was weakened.

Validation covers the production URLSession delegate flow against synthetic intercepted responses and the native MP3 boundary's rejection paths. It does not claim a live ElevenLabs or audible playback acceptance test.

No live API requests, charges, real credentials, microphone capture or audible playback were performed. Tests use clearly fake keys only. Live voice availability, account entitlement and perceived voice quality remain intentionally unverified and belong to the authorized end-user setup flow.
