import AVFoundation
import Foundation

@MainActor protocol LocalSpeechSynthesisDriver: AnyObject {
  var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)? { get set }
  func speak(_ text: String, id: UUID) throws
  func stop()
}

/// Installed macOS voices only. No synthesizer is created until an explicit speech request.
@MainActor public final class NativeSpeechOutput: SpeechOutput {
  public private(set) var isSpeaking = false
  public var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?
  private let makeDriver: @MainActor () -> any LocalSpeechSynthesisDriver
  private var driver: (any LocalSpeechSynthesisDriver)?
  private var activeID: UUID?
  private var watchdog: Task<Void, Never>?

  public convenience init() { self.init(makeDriver: { AVLocalSpeechDriver() }) }

  init(makeDriver: @escaping @MainActor () -> any LocalSpeechSynthesisDriver) {
    self.makeDriver = makeDriver
  }

  /// Completion is always delivered after this method returns its request ID.
  @discardableResult public func speak(_ text: String) -> UUID {
    stop()
    let id = UUID()
    activeID = id
    let bounded = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    guard !bounded.isEmpty else { finish(id, result: .failed); return id }
    if driver == nil {
      let created = makeDriver()
      created.onCompletion = { [weak self] id, result in self?.finish(id, result: result) }
      driver = created
    }
    isSpeaking = true
    do {
      try driver?.speak(bounded, id: id)
      // AVSpeechSynthesizer has no failure delegate. A bounded watchdog fails closed
      // if the OS never produces a finish/cancel event, without restarting capture.
      if activeID == id {
        watchdog = Task { @MainActor [weak self] in
          do { try await Task.sleep(for: .seconds(30)) } catch { return }
          guard let self, self.activeID == id else { return }
          self.finish(id, result: .failed)
          self.driver?.stop()
        }
      }
    } catch {
      finish(id, result: .failed)
      driver?.stop()
    }
    return id
  }

  public func stop() {
    guard let id = activeID else { return }
    finish(id, result: .cancelled)
    driver?.stop()
  }

  private func finish(_ id: UUID, result: SpeechOutputResult) {
    guard activeID == id else { return }
    activeID = nil
    isSpeaking = false
    watchdog?.cancel()
    watchdog = nil
    let completion = onCompletion
    Task { @MainActor in completion?(id, result) }
  }
}

@MainActor private final class AVLocalSpeechDriver: NSObject, LocalSpeechSynthesisDriver,
  AVSpeechSynthesizerDelegate {
  var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?
  private let synthesizer = AVSpeechSynthesizer()
  private var current: (utterance: AVSpeechUtterance, id: UUID)?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(_ text: String, id: UUID) throws {
    // Enumerate installed voices, never request/download an absent voice. Samples are English.
    let installed = AVSpeechSynthesisVoice.speechVoices()
    guard let voice = installed.first(where: { $0.language == "en-US" })
      ?? installed.first(where: { $0.language.hasPrefix("en-") }) else {
      throw LocalVoiceError.noInstalledEnglishVoice
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    current = (utterance, id)
    synthesizer.speak(utterance)
  }

  func stop() {
    current = nil
    synthesizer.stopSpeaking(at: .immediate)
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance) {
    deliver(ObjectIdentifier(utterance), result: .finished)
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance) {
    deliver(ObjectIdentifier(utterance), result: .cancelled)
  }

  nonisolated private func deliver(_ identity: ObjectIdentifier, result: SpeechOutputResult) {
    Task { @MainActor [weak self] in
      guard let self, let current = self.current,
        ObjectIdentifier(current.utterance) == identity else { return }
      self.current = nil
      self.onCompletion?(current.id, result)
    }
  }
}

private enum LocalVoiceError: Error { case noInstalledEnglishVoice }
