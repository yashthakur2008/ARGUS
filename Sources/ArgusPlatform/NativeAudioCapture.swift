import Foundation
import AVFoundation
import Speech

/// The only cross-thread native object holder. All request access and append/end
/// ordering is lock-protected. PCM buffers never escape the audio callback.
final class NativeAudioFrameSink: @unchecked Sendable {
  private let lock = NSLock()
  private var active = false
  private var generation: UInt64 = 0
  private var request: SFSpeechAudioBufferRecognitionRequest?

  func activate() -> UInt64 {
    lock.withLock {
      generation &+= 1
      active = true
      return generation
    }
  }
  func setRequest(_ value: SFSpeechAudioBufferRecognitionRequest?) {
    lock.withLock {
      request?.endAudio()
      request = value
    }
  }
  func deactivate() {
    lock.withLock {
      active = false
      generation &+= 1
      request?.endAudio()
      request = nil
    }
  }

  func consume(_ buffer: AVAudioPCMBuffer, epoch: UInt64) -> (rms: Double, peak: Double)? {
    lock.withLock {
      guard active, generation == epoch, let channels = buffer.floatChannelData,
        buffer.frameLength > 0, buffer.format.channelCount > 0 else { return nil }
      request?.append(buffer)
      var sum = 0.0
      var peak = 0.0
      let count = Int(buffer.frameLength)
      let channelCount = Int(buffer.format.channelCount)
      for channel in 0..<channelCount {
        for frame in 0..<count {
          let sample = Double(channels[channel][frame])
          sum += sample * sample
          peak = max(peak, abs(sample))
        }
      }
      return (sqrt(sum / Double(count * channelCount)), peak)
    }
  }
}

@MainActor final class NativeActivationAudioDriver: ActivationAudioDriver {
  private let sink: NativeAudioFrameSink
  private var engine: AVAudioEngine?
  private var installedTap = false
  private var configurationObserver: (any NSObjectProtocol)?
  private var generation: UInt64 = 0

  init(sink: NativeAudioFrameSink) { self.sink = sink }

  func start(onLevels: @escaping @MainActor @Sendable (Double, Double, Double) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void) throws {
    // No AVAudioEngine exists until the explicitly authorized start reaches here.
    let engine = AVAudioEngine()
    self.engine = engine
    generation &+= 1
    let token = generation
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0,
      format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
      throw NativeActivationError.invalidInput
    }
    let captureEpoch = sink.activate()
    let sink = sink
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      guard let levels = sink.consume(buffer, epoch: captureEpoch) else { return }
      let time = ProcessInfo.processInfo.systemUptime
      Task { @MainActor [weak self] in
        guard let self, self.generation == token, self.engine != nil else { return }
        onLevels(levels.rms, levels.peak, time)
      }
    }
    installedTap = true
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.generation == token, self.engine != nil else { return }
        onFailure("The microphone configuration changed. Check the input device, then enable again.")
      }
    }
    engine.prepare()
    try engine.start()
  }

  func stop() {
    generation &+= 1
    sink.deactivate()
    if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    configurationObserver = nil
    if installedTap { engine?.inputNode.removeTap(onBus: 0) }
    installedTap = false
    engine?.stop()
    engine?.reset()
    engine = nil
  }
}

enum NativeActivationError: Error { case invalidInput, onDeviceSpeechUnavailable }
