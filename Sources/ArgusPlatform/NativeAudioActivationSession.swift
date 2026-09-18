import Foundation
import ArgusCore

/// A consent session owns one capture engine and successive local speech tasks.
/// Capture and speech have separate epochs so renewal cannot revive stale work.
@MainActor final class NativeAudioActivationSession: AudioActivationSession {
  private let audio: any ActivationAudioDriver
  private let speech: any ActivationSpeechDriver
  private let scheduler: any ActivationScheduler
  private let now: @MainActor @Sendable () -> Double
  private var generation: UInt64 = 0
  private var speechEpoch: UInt64 = 0
  private var active = false
  private var timer: (any ActivationTimer)?
  private var speechStartedAt = 0.0
  private var immediateFinals = 0
  private var transcript: (@MainActor @Sendable (String, Double, Bool) -> Void)?
  private var failure: (@MainActor @Sendable (String) -> Void)?

  convenience init() {
    let sink = NativeAudioFrameSink()
    self.init(audio: NativeActivationAudioDriver(sink: sink),
      speech: NativeActivationSpeechDriver(sink: sink), scheduler: NativeActivationScheduler(),
      now: { ProcessInfo.processInfo.systemUptime })
  }

  init(audio: any ActivationAudioDriver, speech: any ActivationSpeechDriver,
    scheduler: any ActivationScheduler, now: @escaping @MainActor @Sendable () -> Double) {
    self.audio = audio
    self.speech = speech
    self.scheduler = scheduler
    self.now = now
  }

  func start(mode: ActivationMode,
    onLevels: @escaping @MainActor @Sendable (Double, Double, Double) -> Void,
    onTranscript: @escaping @MainActor @Sendable (String, Double, Bool) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void) throws {
    stop()
    active = true
    immediateFinals = 0
    transcript = onTranscript
    failure = onFailure
    let token = generation
    do {
      if mode != .clap { try beginSpeech(token: token) }
      guard active, generation == token else { return }
      try audio.start(onLevels: { [weak self] rms, peak, time in
        guard let self, self.active, self.generation == token else { return }
        onLevels(rms, peak, time)
      }, onFailure: { [weak self] message in
        guard let self, self.active, self.generation == token else { return }
        self.fail(message)
      })
    } catch {
      stop()
      throw error
    }
  }

  private func beginSpeech(token: UInt64) throws {
    speechEpoch &+= 1
    let epoch = speechEpoch
    speechStartedAt = now()
    try speech.start(onResult: { [weak self] text, time, final in
      guard let self, self.isCurrent(token, epoch) else { return }
      self.transcript?(text, time, final)
      guard self.isCurrent(token, epoch), final else { return }
      self.renew(token: token, epoch: epoch, normalFinal: true)
    }, onFailure: { [weak self] message in
      guard let self, self.isCurrent(token, epoch) else { return }
      self.fail(message)
    })
    guard isCurrent(token, epoch) else { return }
    // Rotate before Speech's typical one-minute task limit. No new permission
    // request or consent session is created, and every task stays on-device.
    timer = scheduler.schedule(after: 50) { [weak self] in
      guard let self, self.isCurrent(token, epoch) else { return }
      self.transcript?("", self.now(), true)
      guard self.isCurrent(token, epoch) else { return }
      self.renew(token: token, epoch: epoch, normalFinal: false)
    }
  }

  private func renew(token: UInt64, epoch: UInt64, normalFinal: Bool) {
    guard isCurrent(token, epoch) else { return }
    immediateFinals = normalFinal && now() - speechStartedAt < 1 ? immediateFinals + 1 : 0
    guard immediateFinals <= 3 else {
      fail("On-device speech repeatedly ended immediately. Check speech availability, then enable again.")
      return
    }
    speechEpoch &+= 1
    timer?.cancel()
    timer = nil
    speech.stop()
    do { try beginSpeech(token: token) }
    catch { fail("On-device speech could not restart. Check speech availability, then enable again.") }
  }

  private func isCurrent(_ token: UInt64, _ epoch: UInt64) -> Bool {
    active && generation == token && speechEpoch == epoch
  }

  private func fail(_ message: String) {
    let callback = failure
    stop()
    callback?(message)
  }

  func stop() {
    active = false
    generation &+= 1
    speechEpoch &+= 1
    timer?.cancel()
    timer = nil
    audio.stop()
    speech.stop()
    transcript = nil
    failure = nil
  }
}

@MainActor private final class NativeActivationTimer: ActivationTimer {
  private var task: Task<Void, Never>?
  init(seconds: Double, action: @escaping @MainActor @Sendable () -> Void) {
    task = Task {
      do { try await Task.sleep(for: .seconds(seconds)) }
      catch { return }
      guard !Task.isCancelled else { return }
      action()
    }
  }
  func cancel() { task?.cancel(); task = nil }
  deinit { task?.cancel() }
}

@MainActor final class NativeActivationScheduler: ActivationScheduler {
  func schedule(after seconds: Double, action: @escaping @MainActor @Sendable () -> Void) -> any ActivationTimer {
    NativeActivationTimer(seconds: seconds, action: action)
  }
}
