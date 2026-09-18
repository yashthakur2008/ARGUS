import Testing
import AVFoundation
@testable import ArgusPlatform

@Test func nativeFrameSinkMeasuresSyntheticPCMAndRejectsOldCaptureEpoch() throws {
  // An in-memory PCM buffer is not a live audio engine or device.
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
  buffer.frameLength = 4
  let channel = try #require(buffer.floatChannelData?[0])
  channel[0] = 0; channel[1] = 1; channel[2] = 0; channel[3] = -1
  let sink = NativeAudioFrameSink()
  let first = sink.activate()
  let levels = try #require(sink.consume(buffer, epoch: first))
  #expect(abs(levels.rms - 0.70710678118) < 0.00001)
  #expect(levels.peak == 1)
  sink.deactivate()
  #expect(sink.consume(buffer, epoch: first) == nil)
  let second = sink.activate()
  #expect(second != first)
  #expect(sink.consume(buffer, epoch: first) == nil)
  #expect(sink.consume(buffer, epoch: second) != nil)
  sink.deactivate()
}
