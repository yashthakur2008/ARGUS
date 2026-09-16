# Prompt-storage feasibility: Data Protection Keychain and CryptoKit

Date: 2026-09-17 (research completed 2026-09-18 UTC).

**Status: supporting, noncanonical research.** This is not an implementation plan approval, a replacement security specification, or evidence of a working signed security boundary. The controlling requirements remain [the native macOS design](../superpowers/specs/2026-09-17-argus-native-macos-design.md), especially “Security and platform isolation,” and the approved delivery roadmap. Where this note proposes choices not fixed there, they remain proposals.

**Scope performed:** read repository documents and official Apple documentation over HTTPS; write this file only. No shell, app code, build, Keychain query or item, secret/key/nonce generation, agent, installation, signing operation, account inspection/change, permission request, or user-data operation was performed. No cryptographic or signed integration tests were executed for this research. This file is intentionally left for coordinator review and scoped commit.

## Decision summary

1. **The canonical boundary is technically supported on macOS 14+.** Use Security’s `SecItem` API with `kSecUseDataProtectionKeychain = true`, non-synchronizable items, and the broker’s explicitly selected private access group. Apple documents this implementation and entitlement-based boundary. It is not equivalent to the legacy file-based Keychain or its ACLs. [A1, A2, A4]
2. **An ad-hoc development executable is not a substitute for the provisioned boundary.** macOS can run code without a provisioning profile, but Data Protection Keychain access-group entitlements require authorization. A successful Swift package build, an ad-hoc app signature, or adding entitlement strings to a plist does not establish that authorization. Do not fall back to another keychain, a broad shared group, a local key file, or plaintext to make development appear complete. [A1, A3]
3. **Built-in CryptoKit AES-GCM is suitable without a third-party package or service.** The relevant APIs are available from macOS 10.15, below ARGUS’s macOS 14 floor. Real encryption, authentication-failure, envelope, and storage tests can later use explicit public test fixtures and an injected key-provider boundary without accessing a Keychain. Such tests do not prove OS access-group isolation. [A6–A10]
4. **Protected prompt features must fail closed until the production key is available through the authorized broker.** Reminders and nonsensitive metadata may continue independently, but protected content must not be silently saved elsewhere, replaced, exported, searched as if empty, or sent to workers. The current signing/account/runtime state is unverified, not assumed ready or absent.

## What Apple actually requires

### Data Protection Keychain versus the legacy implementation

Apple’s TN3137 distinguishes two macOS implementations. `SecItem` defaults to the file-based keychain on native macOS unless explicitly directed otherwise. `SecKeychain`/legacy APIs always use that file-based implementation. The Data Protection Keychain uses access groups derived from the calling process’s signed entitlements, optionally supplemented by `SecAccessControl`, rather than legacy `SecAccess` ACLs. [A1]

The selector documentation explicitly recommends `kSecUseDataProtectionKeychain = true` for all relevant operations. Setting `kSecAttrSynchronizable = true` also selects iOS-style behavior, but additionally enables iCloud synchronization. That is **not** an acceptable shortcut for ARGUS’s non-synchronizable key requirement. Use the Data Protection selector and explicitly false synchronization instead. [A4, A5]

The Data Protection Keychain is available only in a **user login context**, not to a system `launchd` daemon. Wrapping a command-line tool in an app-like bundle can provide a location for its provisioning profile, but does not remove the user-context requirement. Library code receives the keychain authority of the host process’s main executable, not a separate identity for the library. A normal `swift test` host therefore cannot be treated as the broker just because it imports the same adapter. [A1]

### Private groups and workers

Apple builds the effective group list from, in order: explicit `keychain-access-groups`, the application identifier (`com.apple.application-identifier` on macOS), and application groups. The app identifier provides an app-private group even without configuring a separate shared Keychain group. A dedicated group can also be limited to one broker identity, but is unnecessary if its actual app-private identifier already meets the design. [A2]

**Recommended simplest interpretation:** explicitly pass the broker’s real, authorized app-private group in every item operation. Obtain its exact configured value from the verified signing configuration. Do not fabricate a Team ID or infer a signing prefix solely from a bundle ID. Apple’s profile technote describes an App ID prefix plus bundle ID, and the real signed/profile values are the authority. [A2, A3]

Explicit selection matters even when today’s default happens to be private:

- The first explicit Keychain sharing group becomes the default when adding an item without a group.
- A read query without a group can search all of the caller’s groups.
- App groups can confer Keychain sharing as well as container sharing.
- Signing host and workers with one team does not automatically grant every worker the host’s private group, but provisioning a worker with that group would grant access. [A2]

Workers must have distinct identities and no entitlement granting the broker’s group, no application group that shares it, and no broker API that returns keys or accepts arbitrary credential names. Broker-selected assignment plaintext is a separate, explicitly bounded capability. This note does not claim that sandboxing makes all secrets on the Mac inaccessible to a compromised process.

### Ad-hoc, development, and distribution are different gates

| Build/context | What it can establish | What it cannot establish by itself |
| --- | --- | --- |
| Ad-hoc local executable/app, including “sign to run locally” style development | Domain behavior and real CryptoKit computation with injected nonsecret fixtures; packaging smoke checks within the existing approved scope | Authorization for the canonical Data Protection private group. A locally claimed entitlement is not an Apple-authorized profile grant. |
| Team-signed development app in the user login session | The appropriate place for a future genuine Keychain integration test, **if** its valid signing identity/profile authorize its exact application/group entitlements and its bundle embeds the required profile | Certificate presence alone is not sufficient. Sandbox enablement alone is not sufficient. The actual signed app must be tested. |
| Developer ID distribution | macOS supports profiles for restricted entitlements in this distribution channel | A Developer ID signature without the necessary authorization does not substitute for a profile. Capability support must match the chosen channel. |
| Mac App Store submission / delivered app | App Store processing verifies signing/provisioning and re-signs the app | The final delivered app may not contain an embedded profile because authorization was checked during distribution. Absence of that file in an App Store-delivered app alone is not proof of failure. Do not assume the locally distribution-signed submission archive is a supported runnable test build. |
| System daemon / outside user login context | Not a supported owner for this canonical key | Packaging, signing, or becoming root does not convert this context into the supported Data Protection Keychain user context. |

These conclusions follow from TN3137 and TN3125’s “Entitlements on macOS” and “Profile location.” `keychain-access-groups` is specifically cited as a **restricted** entitlement. App Sandbox configuration is listed among macOS unrestricted entitlements, so a functioning sandbox must not be confused with Keychain-group authorization. TN3161 also warns that a valid code signature does not prove fitness for a particular distribution or execution purpose. [A1, A3, A11]

Here “ad-hoc” means a local signature without a provisioned Apple development identity. It must not be confused with the similarly named certificate/profile-backed iOS Ad Hoc distribution workflow.

## Production adapter shape and fail-closed behavior

This is a design recommendation, not implemented code or authorization to create an item.

A narrow broker-owned key provider should own a fixed service/account/key-version namespace and the exact private group. Each operation should retain the Data Protection selector and explicit group. New items should be explicitly non-synchronizable. Neither arbitrary service names nor group strings should come from prompt text, worker payloads, or imported files. An item’s stored attributes must be checked as appropriate before treating returned bytes as a valid application key.

| Input condition / result | Required protected-content behavior |
| --- | --- |
| Successful lookup with expected key bytes and supported key version | Permit authenticated operations through the broker. Do not expose raw key bytes through general domain objects, worker messages, logs, or exports. |
| Missing/unauthorized signing identity or access group | Report a configuration/security-unavailable state. Do not retry with the group removed or Data Protection disabled. |
| `errSecItemNotFound` | Distinguish genuine first initialization from missing key for existing protected data. Apple documents that a read specifying a group the app does not belong to can also return this status. **It is not proof that the correct key never existed or that provisioning is valid.** |
| Interaction disallowed, authentication failure/cancellation, unavailable service, or any unknown non-success status | Preserve ciphertext and make the protected operation unavailable. No empty-success result, plaintext fallback, automatically weaker accessibility, or repeated background authentication prompts. |
| Malformed key bytes, unsupported key ID, malformed encrypted envelope, wrong key, or GCM authentication failure | Fail before returning plaintext or mutating the record. Preserve evidence of the failed record without logging its content. Do not silently regenerate a key or overwrite the ciphertext. |
| Key missing while ciphertext exists, including copied/restored database | Show an honest recovery state. Never “repair” this by creating a new key under the old identity. A new key cannot decrypt the old data. |
| Duplicate result while deliberately initializing a genuinely new store | Handle the creation race by reading and validating the exact winning item, not deleting it or replacing its key. A Keychain operation and a SQLite transaction are not one atomic transaction. |

Apple explicitly documents **different unauthorized-group results**: `SecItemAdd` can return `errSecMissingEntitlement`, while a matching read can return `errSecItemNotFound`. A negative worker test must not assert that all unauthorized operations return one specific status. It must establish that the worker never receives the synthetic key, cannot update/delete it, and the broker can still read the original item afterward. [A2, A12]

First-time key creation needs an explicit state machine tied to a truly new protected store and verified configuration. A crash after Keychain creation but before SQLite initialization leaves a key to reconcile, not permission to erase arbitrary items. Rotation/recovery/deletion require a later reviewed lifecycle design. This research does not create or rotate keys.

### Lock policy is a separate, explicit choice

The canonical spec fixes the keychain implementation, ownership, and synchronization policy, but not an accessibility class. A conservative candidate is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: Apple documents unlocked-only access and nonmigration to a different device. This requires explaining that copying a database to another Mac is not sufficient to recover its protected bodies. [A13]

That candidate is **not silently adopted here**. Confirm foreground/background requirements and test actual macOS lock/login behavior in the signed app. Do not weaken it to a broader class merely to make a helper or test succeed. Noninteractive authentication behavior can be expressed with an appropriate LocalAuthentication context, whose `interactionNotAllowed` property is documented, but context plumbing and actual return statuses require adapter tests. [A14]

Keychain protection controls subsequent access to an item, not copies already fetched into broker memory. Design bounded key/plaintext lifetimes and invalidation on the chosen lock/session policy. Do not promise automatic memory erasure of every Swift copy, protection against an administrator controlling the process, or that a screen-lock test alone proves all lifecycle properties.

## Built-in CryptoKit AES-GCM feasibility

Apple’s CryptoKit provides `AES.GCM`, `SymmetricKey`, authenticated `seal`, and authenticated `open` on macOS 10.15+. No external dependency, network service, API account, or Secure Enclave requirement is introduced by these APIs. This establishes documented API availability, **not a fresh build result from this research**. [A6–A10]

A small envelope is sufficient for the proposed first protected-prompt slice:

- An explicit envelope/schema version and nonsecret key identifier.
- AES-GCM nonce, ciphertext, and authentication tag. Apple documents `SealedBox.combined` as `nonce || ciphertext || tag`, available for the default 12-byte nonce. Validate input lengths and supported versions before attempting to open it. [A9]
- Deterministically encoded additional authenticated data binding the immutable record ID, immutable prompt version, protected field kind, and envelope/key-version context. This is an ARGUS design recommendation. CryptoKit authenticates additional data but does not choose or serialize application metadata for you. [A7, A8]
- A documented byte/size limit before encryption, after authenticated decryption, and before materializing domain data. The canonical prompt limits still control.

Apple warns that nonces must not be reused for calls to encryption APIs. With `nonce: nil`, `seal` generates a random nonce. Do not derive a production nonce from a timestamp, record ID, or version, and do not turn a test fixture nonce into a production default. Explicit fixed nonce/key bytes belong only to independently reviewed public test vectors, never real content. [A7, A10]

`open` returns plaintext only if decryption and authentication succeed and otherwise throws. Never return unauthenticated bytes, reinterpret a failed envelope as old plaintext, or log the failing body. Authenticated encryption detects tampering of the authenticated inputs, but does not itself prevent replay of an older valid envelope. Immutable version references and storage concurrency checks must address application-level rollback/substitution separately. [A8]

The canonical encrypted fields are prompt bodies, context snapshots, resolved artifacts, and retained variable values, including immutable history. Titles/tags and ordinary scheduling metadata may remain plaintext only with the stated disclosure. Encrypt before passing protected bytes to SQLite so SQL parameters, WAL/journal pages, temporary tables, FTS indexes, audit records, and caches never intentionally receive protected plaintext. Body search is a bounded trusted-memory decrypt-and-match operation, not a plaintext FTS workaround. FileVault and App Sandbox are additional layers, not substitutes for this encryption contract.

## What can be independently tested without signing or Keychain side effects

The following are feasible **future tests**, not tests executed during this research. The existing successful reminder checkpoint does not imply any of them have passed.

| Test boundary | Fixture / observable assertion | What it does not prove |
| --- | --- | --- |
| Real CryptoKit codec | Construct `SymmetricKey(data:)` from published nonsecret fixture bytes and use explicit public vector inputs. Verify exact envelope decoding, round-trip, Unicode/empty/maximum-size cases. [A15] | No production key generation, secure randomness quality, or Keychain isolation evidence. |
| Authentication rejection | Mutate ciphertext, tag, nonce, bound record/version/field metadata, key ID, and fixture key. Assert no plaintext is returned and no store write occurs. | Does not prove that a live app cannot accidentally leak plaintext elsewhere. |
| Key-provider boundary | Inject typed outcomes for absent key, wrong length, entitlement failure, item-not-found, interaction disallowed, authentication failure, duplicate creation, and unknown status. Assert protected save/search/export/queue paths fail closed and no fallback provider is called. | A simulated OSStatus is not a genuine signing/entitlement test. |
| Query construction | Inject a Security-call boundary that records attributes without calling `SecItem`. Assert fixed service/account, explicit private group, Data Protection selector, false synchronization, and no widening on failure. | Correct dictionaries do not prove the running process possesses the asserted entitlements. |
| SQLite integration | Temporary fixture database with a distinctive public sentinel body. Verify writes store an authenticated envelope, rollback leaves no partial version, reopened fixture data decrypts only with the expected provider, and body search adds no plaintext persistent index. Inspect fixture database and ancillary files as a supplementary leakage check. | A sentinel scan does not prove forensic erasure, absence from OS backups, or absence of every memory copy. |
| Lifecycle/recovery | Inject restart between key-provider success and database commit; assert an existing protected store with unavailable key never initializes a replacement, and missing/corrupt content is not shown as an empty successful library. | Does not exercise real Keychain persistence, lock state, or migration across machines. |
| Shipping isolation | Static dependency/composition tests ensure the shipped app cannot select a fixture key using an environment variable, command argument, defaults toggle, or debug fallback. | Does not replace a signed negative worker-access test. |

Fixture providers should be test-target-only or inaccessible from the shipping composition root. An ad-hoc development app using the production provider should show protected storage unavailable if the boundary cannot be satisfied. A test-only in-memory fixture store can support implementation work, but must be clearly labeled and must not accept persistent personal prompt data as a substitute product mode.

## Exact blockers and future acceptance gates

**Known from the sources:** ad-hoc execution and App Sandbox alone do not authorize the canonical private group; an appropriate provisioned app identity in a user login context is required. CryptoKit availability is not the blocking dependency. [A1, A3, A6]

**Unverified project prerequisites:** real broker bundle/application/group identifiers; developer membership and allowed profile capabilities; available signing identity and matching private key; development and distribution profile authorization; final host/worker entitlements; selected key accessibility and lifecycle policy; signed positive/negative tests; store/key migration and recovery behavior. None of the user’s accounts, signing assets, or Keychain contents were inspected. Do not state that they are absent.

**Previously recorded tooling constraint:** the canonical design reports Command Line Tools and no full Xcode application found in the previously searched locations. This research did not recheck installation state. The coordinator’s extracted Swift toolchain and passing reminder tests enable package work but do not manufacture signing identities, profiles, nested-bundle packaging, or App Store validation. Full Xcode/signing release work remains a separate authorized gate, not a requested installation here.

When that gate is authorized, acceptance must include a correctly signed/provisioned broker creating and retrieving a dedicated **synthetic** item, each distinct signed worker failing to retrieve/update/delete it, broker verification that it remains intact, lock/session and restart tests, and inspection of actual packaged/distribution entitlements. Same-team signing should be used for the negative worker case, because absence of the private group, not a conveniently unrelated team, is the intended isolation boundary. No real user secret is needed. Store-delivered builds must be assessed in their actual re-signed form, not judged solely by whether an embedded profile remains. [A2, A3, A11]

**Go now:** testable domain/envelope/storage logic with explicit injected public fixtures and honest unavailable states. **Not yet demonstrated:** production prompt persistence under the canonical broker-only Keychain boundary. **Never the workaround:** legacy keychain fallback, omitted group, worker sharing, plaintext persistence/indexing, developer-wide key, synchronization, or automatic key reset.

## Official Apple sources

All links below were fetched as Apple documentation during this investigation. Their `.md` representations supplied the readable API declarations/availability and article text. Apple Developer Forums search results were not relied on: the attempted forum page returned a security-verification interstitial rather than its answer.

- **[A1]** [TN3137: On Mac keychain APIs and implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains). Keychain implementation choice, user login context, profile/bundle requirement, and host-executable identity for libraries.
- **[A2]** [Sharing access to keychain items among a collection of apps](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps). Private group, group ordering, app-group sharing, explicit group selection, and differing unauthorized add/read outcomes.
- **[A3]** [TN3125: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles). Especially “The how,” “Entitlements on macOS,” and “Profile location.” Profiles authorize restricted entitlements; source entitlement claims alone are insufficient.
- **[A4]** [kSecUseDataProtectionKeychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain). Explicit macOS selector, all-operation recommendation, and non-synchronizing alternative to the synchronization selector.
- **[A5]** [kSecAttrSynchronizable](https://developer.apple.com/documentation/security/ksecattrsynchronizable). False/default excludes synchronized items; true participates in iCloud synchronization.
- **[A6]** [AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm). Built-in CryptoKit algorithm and macOS 10.15 availability.
- **[A7]** [AES.GCM.seal(_:using:nonce:authenticating:)](https://developer.apple.com/documentation/cryptokit/aes/gcm/seal(_:using:nonce:authenticating:)). Authenticated additional data and automatic random nonce when omitted.
- **[A8]** [AES.GCM.open(_:using:authenticating:)](https://developer.apple.com/documentation/cryptokit/aes/gcm/open(_:using:authenticating:)). Plaintext returned after authentication, failure throws.
- **[A9]** [AES.GCM.SealedBox.combined](https://developer.apple.com/documentation/cryptokit/aes/gcm/sealedbox/combined). Nonce/ciphertext/tag layout and default 12-byte nonce condition.
- **[A10]** [AES.GCM.Nonce](https://developer.apple.com/documentation/cryptokit/aes/gcm/nonce). Explicit warning against nonce reuse.
- **[A11]** [TN3161: Inside Code Signing: Certificates](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates). Digital identity, signature-verification limitations, App Store re-signing, and restrictions on locally running submission-signed apps.
- **[A12]** [errSecMissingEntitlement](https://developer.apple.com/documentation/security/errsecmissingentitlement) and [errSecInteractionNotAllowed](https://developer.apple.com/documentation/security/errsecinteractionnotallowed). Status semantics. Apple's generic suggestion to omit a group is **not** adopted because ARGUS explicitly requires the private group.
- **[A13]** [kSecAttrAccessibleWhenUnlockedThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly). Unlocked access and nonmigration to another device.
- **[A14]** [LAContext.interactionNotAllowed](https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed). Explicit control over interactive authentication.
- **[A15]** [SymmetricKey.init(data:)](https://developer.apple.com/documentation/cryptokit/symmetrickey/init(data:)). Key reconstruction from explicit bytes, suitable for isolated public fixtures.

## Coordinator review (2026-09-17 local / 2026-09-18 UTC)

Reviewed offline against the canonical design, delivery roadmap, current root-package target graph, SQLite ownership/migration code, and app composition. The recommendations are consistent with those boundaries and are accepted as supporting research for the [prompt-library slice plan](../superpowers/plans/2026-09-17-prompt-library-slice.md). The Apple-source retrieval and scope statements above describe the original research author's investigation, not this review: links were not re-fetched, and no live Keychain, signing assets, account state, CryptoKit build/test, bundle or application launch was inspected or performed during this review. Source-level feasibility does not establish production authorization or security. Exact identifiers, accessibility/lifecycle policy and signed positive/negative acceptance remain unverified gates, not assumed missing prerequisites.
