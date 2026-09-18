import Testing
import ArgusCore
@testable import ArgusPlatform

@MainActor private final class TestActivationSession: AudioActivationSession {
  var starts = 0
  var stops = 0
  var failureOnStart = false
  var levels: (@MainActor @Sendable (Double, Double, Double) -> Void)?
  var transcript: (@MainActor @Sendable (String, Double, Bool) -> Void)?
  var failure: (@MainActor @Sendable (String) -> Void)?
  func start(mode: ActivationMode,
    onLevels: @escaping @MainActor @Sendable (Double, Double, Double) -> Void,
    onTranscript: @escaping @MainActor @Sendable (String, Double, Bool) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void) throws {
    starts += 1
    levels = onLevels
    transcript = onTranscript
    failure = onFailure
    if failureOnStart { throw TestFailure.unavailable }
  }
  func stop() { stops += 1 }
}
private enum TestFailure: Error { case unavailable }
@MainActor private final class TestActivationBackend: AudioActivationBackend {
  var micAllowed = true
  var speechAllowed = true
  var pauseMic = false
  var pauseSpeech = false
  var micRequests = 0
  var speechRequests = 0
  var micContinuation: CheckedContinuation<Bool, Never>?
  var speechContinuation: CheckedContinuation<Bool, Never>?
  var sessions: [TestActivationSession] = []
  var failSessionStart = false
  func requestMicrophonePermission() async -> Bool {
    micRequests += 1
    if pauseMic { return await withCheckedContinuation { micContinuation = $0 } }
    return micAllowed
  }
  func requestSpeechPermission() async -> Bool {
    speechRequests += 1
    if pauseSpeech { return await withCheckedContinuation { speechContinuation = $0 } }
    return speechAllowed
  }
  func makeSession() -> any AudioActivationSession {
    let session = TestActivationSession()
    session.failureOnStart = failSessionStart
    sessions.append(session)
    return session
  }
}
@MainActor @Test func activationClapNeverRequestsSpeech() async {
  let backend = TestActivationBackend()
  let service = LocalAudioActivationService(backend: backend)
  #expect(service.state == .stopped)
  #expect(backend.micRequests == 0)
  await service.start(mode: .clap)
  #expect(service.state == .listening(.clap))
  #expect(backend.micRequests == 1)
  #expect(backend.speechRequests == 0)
  #expect(backend.sessions.count == 1)
  service.stop()
  #expect(service.state == .stopped)
  #expect(backend.sessions.first?.stops == 1)
}
@MainActor @Test func activationStopFencesMicrophonePermission() async {
  let backend = TestActivationBackend()
  backend.pauseMic = true
  let service = LocalAudioActivationService(backend: backend)
  let start = Task { await service.start(mode: .both) }
  while backend.micContinuation == nil { await Task.yield() }
  #expect(service.state == .requestingPermission)
  service.stop()
  backend.micContinuation?.resume(returning: true)
  await start.value
  #expect(service.state == .stopped)
  #expect(backend.speechRequests == 0)
  #expect(backend.sessions.isEmpty)
}
@MainActor @Test func activationStopFencesSpeechPermission() async {
  let backend = TestActivationBackend()
  backend.pauseSpeech = true
  let service = LocalAudioActivationService(backend: backend)
  let start = Task { await service.start(mode: .wakeWord) }
  while backend.speechContinuation == nil { await Task.yield() }
  service.stop()
  backend.speechContinuation?.resume(returning: true)
  await start.value
  #expect(service.state == .stopped)
  #expect(backend.sessions.isEmpty)
}
@MainActor @Test func activationDenialAndNativeFailureAreUnavailable() async {
  let backend = TestActivationBackend()
  let service = LocalAudioActivationService(backend: backend)
  backend.micAllowed = false
  await service.start(mode: .both)
  guard case .unavailable = service.state else { Issue.record("Denied microphone must be unavailable"); return }
  #expect(backend.speechRequests == 0)
  #expect(backend.sessions.isEmpty)
  backend.micAllowed = true
  backend.speechAllowed = false
  await service.start(mode: .both)
  guard case .unavailable = service.state else { Issue.record("Denied speech must be unavailable"); return }
  #expect(backend.sessions.isEmpty)
  backend.speechAllowed = true
  backend.failSessionStart = true
  await service.start(mode: .both)
  guard case .unavailable = service.state else { Issue.record("Native failure must be unavailable"); return }
  #expect(backend.sessions.first?.stops == 1)
}
@MainActor @Test func activationOldSessionCallbacksCannotAffectNewSession() async {
  let backend = TestActivationBackend()
  let service = LocalAudioActivationService(backend: backend)
  var triggers: [ActivationTrigger] = []
  service.onActivation = { triggers.append($0) }
  await service.start(mode: .both)
  guard let first = backend.sessions.first else { Issue.record("Missing first session"); return }
  await service.start(mode: .wakeWord)
  first.transcript?("argus", 1, false)
  first.failure?("old failure")
  #expect(triggers.isEmpty)
  #expect(service.state == .listening(.wakeWord))
  backend.sessions.last?.transcript?("argus", 2, false)
  #expect(triggers == [.wakeWord])
  backend.sessions.last?.failure?("Recognition ended. Enable again.")
  #expect(service.state == .unavailable("Recognition ended. Enable again."))
  #expect(backend.sessions.last?.stops == 1)
  backend.sessions.last?.transcript?("argus", 4, true)
  #expect(triggers == [.wakeWord])
}

@MainActor @Test func activationCancellationAndReplacementFencePermission() async {
  let backend = TestActivationBackend()
  backend.pauseMic = true
  let service = LocalAudioActivationService(backend: backend)
  let oldStart = Task { await service.start(mode: .both) }
  while backend.micContinuation == nil { await Task.yield() }
  let continuation = backend.micContinuation
  oldStart.cancel()
  backend.pauseMic = false
  await service.start(mode: .clap)
  continuation?.resume(returning: false)
  await oldStart.value
  #expect(service.state == .listening(.clap))
  #expect(backend.speechRequests == 0)
  #expect(backend.sessions.count == 1)
}
@MainActor @Test func activationSynchronousStopFromStateCallbackPreventsPermissions() async {
  let backend = TestActivationBackend()
  let service = LocalAudioActivationService(backend: backend)
  service.onStateChange = { [weak service] state in
    if state == .requestingPermission { service?.stop() }
  }
  await service.start(mode: .both)
  #expect(service.state == .stopped)
  #expect(backend.micRequests == 0)
}

@MainActor struct AuthorizedOnlyActivationTests {
  @Test func automaticStartNeverCallsPermissionRequests() async {
    let backend = AuthorizedOnlyBackendFake()
    let service = LocalAudioActivationService(backend: backend)
    await service.startIfAuthorized(mode: .both)
    #expect(backend.requests == 0)
    #expect(service.state == .listening(.both))
    #expect(backend.capture.starts == 1)
  }

  @Test func automaticStartDeniedDoesNotRequestOrCapture() async {
    let backend = AuthorizedOnlyBackendFake()
    backend.authorized = false
    let service = LocalAudioActivationService(backend: backend)
    await service.startIfAuthorized(mode: .clap)
    #expect(backend.requests == 0)
    #expect(backend.capture.starts == 0)
    guard case .unavailable = service.state else {
      Issue.record("Expected actionable authorization requirement")
      return
    }
  }
}

@MainActor private final class AuthorizedOnlyBackendFake: AudioActivationBackend {
  var requests = 0
  var authorized = true
  let capture = AuthorizedOnlySessionFake()
  func existingPermissionsAllow(mode: ActivationMode) -> Bool { authorized }
  func requestMicrophonePermission() async -> Bool { requests += 1; return true }
  func requestSpeechPermission() async -> Bool { requests += 1; return true }
  func makeSession() -> any AudioActivationSession { capture }
}
@MainActor private final class AuthorizedOnlySessionFake: AudioActivationSession {
  var starts = 0
  func start(mode: ActivationMode,
    onLevels: @escaping @MainActor @Sendable (Double, Double, Double) -> Void,
    onTranscript: @escaping @MainActor @Sendable (String, Double, Bool) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void) throws { starts += 1 }
  func stop() {}
}
