import ArgusCore

public enum AudioActivationState: Sendable, Equatable {
  case stopped, requestingPermission, listening(ActivationMode), unavailable(String)
}
@MainActor public protocol AudioActivationService: AnyObject {
  var state: AudioActivationState { get }
  var onActivation: (@MainActor @Sendable (ActivationTrigger) -> Void)? { get set }
  var onStateChange: (@MainActor @Sendable (AudioActivationState) -> Void)? { get set }
  func start(mode: ActivationMode) async
  func startIfAuthorized(mode: ActivationMode) async
  func stop()
}

public extension AudioActivationService {
  /// Older adapters must fail closed rather than fall back to a prompting start.
  func startIfAuthorized(mode: ActivationMode) async { stop() }
}

/// Permission and capture boundaries are injected without constructing an audio engine.
@MainActor public protocol AudioActivationBackend: AnyObject {
  func existingPermissionsAllow(mode: ActivationMode) -> Bool
  func requestMicrophonePermission() async -> Bool
  func requestSpeechPermission() async -> Bool
  func makeSession() -> any AudioActivationSession
}
public extension AudioActivationBackend {
  func existingPermissionsAllow(mode: ActivationMode) -> Bool { false }
}
@MainActor public protocol AudioActivationSession: AnyObject {
  func start(
    mode: ActivationMode,
    onLevels: @escaping @MainActor @Sendable (Double, Double, Double) -> Void,
    onTranscript: @escaping @MainActor @Sendable (String, Double, Bool) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void
  ) throws
  func stop()
}

@MainActor public final class LocalAudioActivationService: AudioActivationService {
  public private(set) var state: AudioActivationState = .stopped
  public var onActivation: (@MainActor @Sendable (ActivationTrigger) -> Void)?
  public var onStateChange: (@MainActor @Sendable (AudioActivationState) -> Void)?
  private let backend: any AudioActivationBackend
  private var session: (any AudioActivationSession)?
  private var generation: UInt64 = 0
  private var clap = ClapDetector()
  private var wakeWord = WakeWordDetector()

  public convenience init() { self.init(backend: NativeAudioActivationBackend()) }

  public init(backend: any AudioActivationBackend) { self.backend = backend }

  public func start(mode: ActivationMode) async {
    await start(mode: mode, requestingPermissions: true)
  }

  public func startIfAuthorized(mode: ActivationMode) async {
    await start(mode: mode, requestingPermissions: false)
  }

  private func start(mode: ActivationMode, requestingPermissions: Bool) async {
    tearDown()
    let token = generation
    guard !Task.isCancelled else { setState(.stopped); return }
    setState(.requestingPermission)
    await withTaskCancellationHandler {
      await begin(mode: mode, token: token, requestingPermissions: requestingPermissions)
    } onCancel: {
      Task { @MainActor [weak self] in
        guard let self, self.generation == token else { return }
        self.stop()
      }
    }
  }

  private func begin(mode: ActivationMode, token: UInt64, requestingPermissions: Bool) async {
    guard isCurrent(token) else { return }
    if requestingPermissions {
      let microphoneAllowed = await backend.requestMicrophonePermission()
      guard isCurrent(token) else { return }
      guard microphoneAllowed else {
        fail("Microphone access is denied. Allow ARGUS in System Settings > Privacy & Security > Microphone, then enable again.")
        return
      }
      if mode != .clap {
        let speechAllowed = await backend.requestSpeechPermission()
        guard isCurrent(token) else { return }
        guard speechAllowed else {
          fail("Speech recognition access is denied. Allow ARGUS in System Settings > Privacy & Security > Speech Recognition, then enable again.")
          return
        }
      }
    } else {
      guard backend.existingPermissionsAllow(mode: mode) else {
        fail("Enable listening to review microphone and speech permissions.")
        return
      }
    }
    let capture = backend.makeSession()
    guard isCurrent(token) else { capture.stop(); return }
    session = capture
    do {
      try capture.start(mode: mode, onLevels: { [weak self] rms, peak, time in
        guard let self, self.generation == token, mode != .wakeWord else { return }
        if self.clap.process(rms: rms, peak: peak, at: time) { self.onActivation?(.clap) }
      }, onTranscript: { [weak self] text, time, final in
        guard let self, self.generation == token, mode != .clap else { return }
        if self.wakeWord.process(text, at: time, isFinal: final) { self.onActivation?(.wakeWord) }
      }, onFailure: { [weak self] message in
        guard let self, self.generation == token else { return }
        self.fail(message)
      })
      guard isCurrent(token) else { return }
      setState(.listening(mode))
    } catch {
      guard isCurrent(token) else { return }
      fail("Audio activation could not start. Check the microphone and on-device speech availability, then enable again.")
    }
  }

  public func stop() {
    tearDown()
    setState(.stopped)
  }

  private func isCurrent(_ token: UInt64) -> Bool {
    guard generation == token else { return false }
    if Task.isCancelled { stop(); return false }
    return true
  }

  private func tearDown() {
    generation &+= 1
    let previous = session
    session = nil
    previous?.stop()
    clap.reset()
    wakeWord.reset()
  }

  private func fail(_ message: String) {
    tearDown()
    setState(.unavailable(message))
  }

  private func setState(_ value: AudioActivationState) {
    state = value
    onStateChange?(value)
  }
}
