import Foundation
import Speech

@MainActor final class NativeActivationSpeechDriver: ActivationSpeechDriver {
  private let sink: NativeAudioFrameSink
  private var recognizer: SFSpeechRecognizer?
  private var availabilityObserver: NativeSpeechAvailabilityObserver?
  private var task: SFSpeechRecognitionTask?
  private var generation: UInt64 = 0

  init(sink: NativeAudioFrameSink) { self.sink = sink }

  func start(onResult: @escaping @MainActor @Sendable (String, Double, Bool) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void) throws {
    generation &+= 1
    let token = generation
    // Wake-name recognition currently uses US English. Missing local language
    // resources are an unavailable state, never a reason to use hosted speech.
    let locale = Locale(identifier: "en-US")
    guard let recognizer = SFSpeechRecognizer(locale: locale),
      OnDeviceSpeechPolicy.permitsRecognition(
        languageSupported: OnDeviceSpeechPolicy.supports(locale: locale,
          supportedLocales: SFSpeechRecognizer.supportedLocales()),
        available: recognizer.isAvailable, supportsOnDevice: recognizer.supportsOnDeviceRecognition)
    else { throw NativeActivationError.onDeviceSpeechUnavailable }
    self.recognizer = recognizer
    let observer = NativeSpeechAvailabilityObserver { [weak self] in
      guard let self, self.generation == token else { return }
      onFailure("On-device speech became unavailable. Check local speech availability, then enable again.")
    }
    availabilityObserver = observer
    recognizer.delegate = observer
    let request = NativeSpeechRequest.make()
    sink.setRequest(request)
    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      // Never retain or log the result object or the error's potentially private
      // description. Only this ephemeral string crosses to the detector actor.
      let text = result?.bestTranscription.formattedString
      let final = result?.isFinal ?? false
      let failed = error != nil
      let time = ProcessInfo.processInfo.systemUptime
      Task { @MainActor [weak self] in
        guard let self, self.generation == token else { return }
        if failed {
          onFailure("On-device speech recognition failed. Check local speech availability, then enable again.")
          return
        }
        guard let text else {
          onFailure("On-device speech returned no result. Check local speech availability, then enable again.")
          return
        }
        onResult(text, time, final)
      }
    }
  }

  func stop() {
    generation &+= 1
    sink.setRequest(nil)
    task?.cancel()
    task = nil
    recognizer?.delegate = nil
    availabilityObserver = nil
    recognizer = nil
  }
}

/// Creating a request does not start recognition or touch an audio device.
@MainActor enum NativeSpeechRequest {
  static func make() -> SFSpeechAudioBufferRecognitionRequest {
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    request.contextualStrings = ["Argus"]
    request.taskHint = .confirmation
    return request
  }
}

/// Speech availability changes are an interruption, not permission to fall back.
@MainActor final class NativeSpeechAvailabilityObserver: NSObject, SFSpeechRecognizerDelegate {
  private let onUnavailable: @MainActor @Sendable () -> Void
  init(onUnavailable: @escaping @MainActor @Sendable () -> Void) { self.onUnavailable = onUnavailable }
  nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
    Task { @MainActor [weak self] in self?.availabilityChanged(available) }
  }
  func availabilityChanged(_ available: Bool) {
    if !available { onUnavailable() }
  }
}
