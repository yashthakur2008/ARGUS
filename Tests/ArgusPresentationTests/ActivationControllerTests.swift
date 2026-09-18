import Testing
import ArgusCore
import ArgusPlatform
@testable import ArgusPresentation

@MainActor struct ActivationControllerTests {
  @Test func disabledInitializationAndPreviewNeverStartAudio() {
    let service = PresentationAudioFake()
    var feedback: [ActivationTrigger?] = []
    let controller = ActivationController(service: service) { feedback.append($0) }
    #expect(controller.status == .stopped)
    #expect(controller.mode == .clap)
    #expect(service.starts.isEmpty)
    controller.preview()
    #expect(feedback.count == 1)
    #expect(feedback.first == .some(nil))
    #expect(service.starts.isEmpty)
  }

  @Test func enabledEventsUpdateStatusAndFeedback() async {
    let service = PresentationAudioFake()
    var feedback: [ActivationTrigger?] = []
    let controller = ActivationController(service: service) { feedback.append($0) }
    controller.mode = .both
    await controller.enable()
    #expect(service.starts == [.both])
    #expect(controller.status == .listening(.both))
    service.onActivation?(.clap)
    service.onActivation?(.wakeWord)
    #expect(feedback == [.clap, .wakeWord])
    let callbackBeforeFailure = service.onActivation
    service.onStateChange?(.unavailable("On-device speech unavailable"))
    #expect(controller.status == .unavailable("On-device speech unavailable"))
    #expect(controller.mode == .both)
    callbackBeforeFailure?(.clap)
    service.onStateChange?(.listening(.both))
    #expect(feedback == [.clap, .wakeWord])
    #expect(controller.status == .unavailable("On-device speech unavailable"))
    controller.stop()
    #expect(controller.status == .stopped)
    #expect(service.stops == 1)
  }

  @Test func stopRejectsCapturedCallbacksAndPendingStart() async throws {
    let service = PresentationAudioFake()
    service.suspendStart = true
    var feedbackCount = 0
    let controller = ActivationController(service: service) { _ in feedbackCount += 1 }
    let start = Task { await controller.enable() }
    for _ in 0..<1_000 {
      if service.continuation != nil { break }
      await Task.yield()
    }
    try #require(service.continuation != nil)
    #expect(controller.status == .requestingPermission)
    let staleState = service.onStateChange
    let staleActivation = service.onActivation
    controller.stop()
    #expect(!controller.canEnable)
    await controller.enable()
    #expect(service.starts.count == 1)
    staleState?(.listening(.clap))
    staleActivation?(.clap)
    service.finishStart()
    await start.value
    #expect(controller.status == .stopped)
    #expect(feedbackCount == 0)
    #expect(service.state == .stopped)
    #expect(controller.canEnable)
    await controller.enable()
    staleState?(.unavailable("old session"))
    staleActivation?(.wakeWord)
    #expect(controller.status == .listening(.clap))
    #expect(feedbackCount == 0)
    service.onActivation?(.clap)
    #expect(feedbackCount == 1)
  }

  @Test func duplicateEnableDoesNotStartTwice() async {
    let service = PresentationAudioFake()
    let controller = ActivationController(service: service) { _ in }
    await controller.enable()
    await controller.enable()
    #expect(service.starts.count == 1)
  }

  @Test func realServiceStartKeepsControllerListeningAndStopTearsDown() async {
    let backend = PresentationBackendFake()
    let service = LocalAudioActivationService(backend: backend)
    var feedback: [ActivationTrigger?] = []
    let controller = ActivationController(service: service) { feedback.append($0) }
    #expect(backend.microphoneRequests == 0)
    controller.mode = .wakeWord
    await controller.enable()
    #expect(controller.status == .listening(.wakeWord))
    #expect(service.state == .listening(.wakeWord))
    #expect(backend.microphoneRequests == 1)
    #expect(backend.speechRequests == 1)
    backend.capture.onTranscript?("argus", 1, true)
    #expect(feedback == [.wakeWord])
    controller.stop()
    #expect(backend.capture.stops == 1)
    #expect(controller.status == .stopped)
    backend.capture.onTranscript?("argus", 10, true)
    #expect(feedback == [.wakeWord])
  }

  @Test func speechDeniedRemainsVisibleAndDoesNotSilentlyFallBack() async {
    let backend = PresentationBackendFake()
    backend.speechAllowed = false
    let service = LocalAudioActivationService(backend: backend)
    let controller = ActivationController(service: service) { _ in }
    controller.mode = .both
    await controller.enable()
    guard case .unavailable(let message) = controller.status else {
      Issue.record("Expected a visible permission error")
      return
    }
    #expect(message.contains("Speech"))
    #expect(controller.mode == .both)
    #expect(!controller.isEnabled)
    #expect(backend.capture.starts == 0)
    #expect(service.state == controller.status)
    controller.mode = .clap
    #expect(backend.capture.starts == 0)
    await controller.enable()
    #expect(controller.status == .listening(.clap))
    #expect(backend.speechRequests == 1)
  }
}

@MainActor private final class PresentationAudioFake: AudioActivationService {
  var state: AudioActivationState = .stopped
  var onActivation: (@MainActor @Sendable (ActivationTrigger) -> Void)?
  var onStateChange: (@MainActor @Sendable (AudioActivationState) -> Void)?
  var starts: [ActivationMode] = []
  var stops = 0
  var suspendStart = false
  var continuation: CheckedContinuation<Void, Never>?

  func start(mode: ActivationMode) async {
    starts.append(mode)
    state = .requestingPermission
    onStateChange?(state)
    if suspendStart { await withCheckedContinuation { continuation = $0 } }
    state = .listening(mode)
    onStateChange?(state)
  }
  func finishStart() {
    suspendStart = false
    continuation?.resume()
    continuation = nil
  }
  func stop() {
    stops += 1
    state = .stopped
    onStateChange?(state)
  }
}

@MainActor private final class PresentationBackendFake: AudioActivationBackend {
  var microphoneRequests = 0
  var speechRequests = 0
  var speechAllowed = true
  let capture = PresentationSessionFake()
  func requestMicrophonePermission() async -> Bool { microphoneRequests += 1; return true }
  func requestSpeechPermission() async -> Bool { speechRequests += 1; return speechAllowed }
  func makeSession() -> any AudioActivationSession { capture }
}

@MainActor private final class PresentationSessionFake: AudioActivationSession {
  var starts = 0
  var stops = 0
  var onTranscript: (@MainActor @Sendable (String, Double, Bool) -> Void)?
  func start(mode: ActivationMode,
    onLevels: @escaping @MainActor @Sendable (Double, Double, Double) -> Void,
    onTranscript: @escaping @MainActor @Sendable (String, Double, Bool) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void) throws {
    starts += 1
    self.onTranscript = onTranscript
  }
  func stop() { stops += 1 }
}
