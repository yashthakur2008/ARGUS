import ArgusCore
import ArgusPlatform
import Foundation
import Observation

/// One consent session shared by windows and the menu bar. Never starts capture on initialization.
@MainActor @Observable
public final class ActivationController {
  public private(set) var status: AudioActivationState = .stopped
  public var mode: ActivationMode = .clap {
    didSet { if oldValue != mode { intentGeneration &+= 1 } }
  }
  // Also fences coordinator speech resumes against legacy direct Stop/mode changes.
  private(set) var intentGeneration: UInt64 = 0
  public var isListening: Bool {
    if case .listening = status { return true }
    return false
  }
  public var isEnabled: Bool { status == .requestingPermission || isListening }
  public var canEnable: Bool { !isEnabled && !startInFlight }
  public var statusText: String {
    switch status {
    case .stopped: "Microphone off"
    case .requestingPermission: "Waiting for permission…"
    case .listening(let mode): "Listening · \(mode.displayName)"
    case .unavailable(let reason): "Listening unavailable: \(reason)"
    }
  }

  private let service: any AudioActivationService
  private let onFeedback: @MainActor (ActivationTrigger?) -> Void
  private var session: UUID?
  private var startInFlight = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  public init(service: any AudioActivationService,
    onFeedback: @escaping @MainActor (ActivationTrigger?) -> Void) {
    self.service = service
    self.onFeedback = onFeedback
  }

  public func enable() async { await enable(requestingPermissions: true) }

  /// Never invokes a permission request, including when authorization changes between checks.
  public func enableIfAuthorized() async { await enable(requestingPermissions: false) }

  func waitForPendingStart() async {
    guard startInFlight else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  private func enable(requestingPermissions: Bool) async {
    guard canEnable else { return }
    intentGeneration &+= 1
    let token = UUID()
    session = token
    startInFlight = true
    status = .requestingPermission
    service.onStateChange = { [weak self] state in
      guard let self, self.session == token else { return }
      self.status = state
      if case .stopped = state { self.session = nil }
      if case .unavailable = state { self.session = nil }
    }
    service.onActivation = { [weak self] trigger in
      guard let self, self.session == token, self.isListening else { return }
      self.onFeedback(trigger)
    }
    if requestingPermissions { await service.start(mode: mode) }
    else { await service.startIfAuthorized(mode: mode) }
    startInFlight = false
    defer {
      let waiters = startWaiters
      startWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
    // Serialize starts so cleanup of an old permission request cannot stop a newer session.
    guard session == token else {
      service.onActivation = nil
      service.onStateChange = nil
      // A service failure has already torn down capture. Keep its actionable error state.
      switch service.state {
      case .unavailable: break
      default: service.stop()
      }
      return
    }
    status = service.state
  }

  public func stop() {
    intentGeneration &+= 1
    session = nil
    service.onActivation = nil
    service.onStateChange = nil
    service.stop()
    status = .stopped
  }

  /// Visual feedback only. Does not request permission or invoke the audio service.
  public func preview() { onFeedback(nil) }
}

extension ActivationMode {
  var displayName: String {
    switch self {
    case .clap: "Clap"
    case .wakeWord: "Say Argus"
    case .both: "Clap or say Argus"
    }
  }
}
