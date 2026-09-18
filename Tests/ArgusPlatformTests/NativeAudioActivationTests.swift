import Testing
@testable import ArgusPlatform

@Test func nativeSpeechFailsClosedWithoutEveryCapability() {
  for language in [false, true] {
    for available in [false, true] {
      for onDevice in [false, true] {
        #expect(OnDeviceSpeechPolicy.permitsRecognition(languageSupported: language,
          available: available, supportsOnDevice: onDevice) == (language && available && onDevice))
      }
    }
  }
}

import ArgusCore

@MainActor private final class FakeAudioDriver: ActivationAudioDriver {
  var starts = 0
  var stops = 0
  var levels: (@MainActor @Sendable (Double, Double, Double) -> Void)?
  var failure: (@MainActor @Sendable (String) -> Void)?
  func start(onLevels: @escaping @MainActor @Sendable (Double, Double, Double) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void) throws {
    starts += 1; levels = onLevels; failure = onFailure
  }
  func stop() { stops += 1 }
}
@MainActor private final class FakeSpeechDriver: ActivationSpeechDriver {
  var starts = 0
  var stops = 0
  var failStart = false
  var results: [@MainActor @Sendable (String, Double, Bool) -> Void] = []
  var failures: [@MainActor @Sendable (String) -> Void] = []
  func start(onResult: @escaping @MainActor @Sendable (String, Double, Bool) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void) throws {
    starts += 1
    results.append(onResult); failures.append(onFailure)
    if failStart { throw NativeTestError.failed }
  }
  func stop() { stops += 1 }
}
private enum NativeTestError: Error { case failed }
@MainActor private final class FakeActivationTimer: ActivationTimer {
  var cancelled = false
  let action: @MainActor @Sendable () -> Void
  init(_ action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
  func cancel() { cancelled = true }
}
@MainActor private final class FakeActivationScheduler: ActivationScheduler {
  var timers: [FakeActivationTimer] = []
  func schedule(after seconds: Double, action: @escaping @MainActor @Sendable () -> Void) -> any ActivationTimer {
    let timer = FakeActivationTimer(action); timers.append(timer); return timer
  }
}
@MainActor @Test func nativeNormalFinalRenewsAndFencesOldRecognition() throws {
  let audio = FakeAudioDriver(), speech = FakeSpeechDriver(), scheduler = FakeActivationScheduler()
  let clock = NativeTestClock()
  let session = NativeAudioActivationSession(audio: audio, speech: speech, scheduler: scheduler, now: { clock.time })
  var transcripts: [String] = [], failures: [String] = []
  try session.start(mode: .both, onLevels: { _,_,_ in }, onTranscript: { text,_,_ in transcripts.append(text) }, onFailure: { failures.append($0) })
  #expect(audio.starts == 1)
  #expect(speech.starts == 1)
  guard let first = speech.results.first else { Issue.record("Speech was not started"); return }
  clock.time = 4
  first("argus", clock.time, true)
  #expect(speech.starts == 2)
  #expect(audio.starts == 1)
  first("late argus", clock.time, true)
  speech.failures.first?("late failure")
  #expect(transcripts == ["argus"])
  #expect(failures.isEmpty)
  #expect(speech.starts == 2)
  session.stop()
  speech.results.last?("stopped", 5, true)
  scheduler.timers.last?.action()
  audio.failure?("stopped config change")
  #expect(speech.starts == 2)
  #expect(failures.isEmpty)
  #expect(transcripts == ["argus"])
  let allCancelled = scheduler.timers.allSatisfy { $0.cancelled }
  #expect(allCancelled)
}
@MainActor @Test func nativeTimerRenewsClearsUtteranceAndFencesOldTimer() throws {
  let audio = FakeAudioDriver(), speech = FakeSpeechDriver(), scheduler = FakeActivationScheduler()
  let clock = NativeTestClock()
  let session = NativeAudioActivationSession(audio: audio, speech: speech, scheduler: scheduler, now: { clock.time })
  var finalResets = 0
  try session.start(mode: .wakeWord, onLevels: { _,_,_ in }, onTranscript: { text,_,final in
    if text.isEmpty && final { finalResets += 1 }
  }, onFailure: { _ in Issue.record("Unexpected failure") })
  guard let first = scheduler.timers.first else { Issue.record("Missing renewal timer"); return }
  clock.time = 50
  first.action()
  #expect(speech.starts == 2)
  #expect(finalResets == 1)
  first.action()
  #expect(speech.starts == 2)
  session.stop()
}
@MainActor @Test func nativeImmediateFinalLoopAndErrorsStopCapture() throws {
  let audio = FakeAudioDriver(), speech = FakeSpeechDriver(), scheduler = FakeActivationScheduler()
  let session = NativeAudioActivationSession(audio: audio, speech: speech, scheduler: scheduler, now: { 0 })
  var failures = 0
  try session.start(mode: .both, onLevels: { _,_,_ in }, onTranscript: { _,_,_ in }, onFailure: { _ in failures += 1 })
  for _ in 0..<8 { speech.results.last?("", 0, true) }
  #expect(failures == 1)
  #expect(speech.starts <= 4)
  #expect(audio.stops >= 1)
  let allCancelled = scheduler.timers.allSatisfy { $0.cancelled }
  #expect(allCancelled)
}
@MainActor @Test func nativeSpeechFailureNeverRenewsAndClapNeverStartsSpeech() throws {
  let audio = FakeAudioDriver(), speech = FakeSpeechDriver(), scheduler = FakeActivationScheduler()
  let session = NativeAudioActivationSession(audio: audio, speech: speech, scheduler: scheduler, now: { 0 })
  var failures = 0
  try session.start(mode: .both, onLevels: { _,_,_ in }, onTranscript: { _,_,_ in }, onFailure: { _ in failures += 1 })
  speech.failures.last?("recognition failed")
  scheduler.timers.last?.action()
  #expect(failures == 1)
  #expect(speech.starts == 1)
  try session.start(mode: .clap, onLevels: { _,_,_ in }, onTranscript: { _,_,_ in }, onFailure: { _ in })
  #expect(speech.starts == 1)
  #expect(audio.starts == 2)
  session.stop()
}

@MainActor @Test func nativeStopInsideFinalAndTimerCallbacksPreventsRenewal() throws {
  for stopOnTimer in [false, true] {
    let audio = FakeAudioDriver(), speech = FakeSpeechDriver(), scheduler = FakeActivationScheduler()
    let session = NativeAudioActivationSession(audio: audio, speech: speech, scheduler: scheduler, now: { 4 })
    try session.start(mode: .both, onLevels: { _,_,_ in }, onTranscript: { _,_,_ in session.stop() }, onFailure: { _ in })
    if stopOnTimer { scheduler.timers.first?.action() }
    else { speech.results.first?("argus", 4, true) }
    #expect(speech.starts == 1)
    #expect(audio.stops >= 1)
    let cancelled = scheduler.timers.allSatisfy { $0.cancelled }
    #expect(cancelled)
  }
}
@MainActor @Test func nativeRenewalStartFailureStopsAndFencesCallbacks() throws {
  let audio = FakeAudioDriver(), speech = FakeSpeechDriver(), scheduler = FakeActivationScheduler()
  let session = NativeAudioActivationSession(audio: audio, speech: speech, scheduler: scheduler, now: { 4 })
  var failures = 0, transcripts = 0
  try session.start(mode: .both, onLevels: { _,_,_ in }, onTranscript: { _,_,_ in transcripts += 1 }, onFailure: { _ in failures += 1 })
  speech.failStart = true
  speech.results.first?("argus", 4, true)
  #expect(failures == 1)
  #expect(audio.stops >= 1)
  speech.results.last?("late result", 5, true)
  scheduler.timers.first?.action()
  #expect(transcripts == 1)
  #expect(failures == 1)
}
@MainActor @Test func nativeConfigurationFailureStopsCaptureAndSpeech() throws {
  let audio = FakeAudioDriver(), speech = FakeSpeechDriver(), scheduler = FakeActivationScheduler()
  let session = NativeAudioActivationSession(audio: audio, speech: speech, scheduler: scheduler, now: { 4 })
  var failures = 0, levels = 0
  try session.start(mode: .both, onLevels: { _,_,_ in levels += 1 }, onTranscript: { _,_,_ in }, onFailure: { _ in failures += 1 })
  audio.failure?("input changed")
  audio.levels?(0.3, 0.9, 5)
  scheduler.timers.first?.action()
  #expect(failures == 1)
  #expect(levels == 0)
  #expect(speech.starts == 1)
  #expect(audio.stops >= 1)
  #expect(speech.stops >= 1)
}

@MainActor private final class NativeTestClock { var time = 0.0 }

@MainActor @Test func nativeSpeechRequestAlwaysRequiresOnDeviceRecognition() {
  let request = NativeSpeechRequest.make()
  #expect(request.requiresOnDeviceRecognition)
  #expect(request.shouldReportPartialResults)
  #expect(request.contextualStrings == ["Argus"])
}

import Foundation

@Test func nativeSpeechLocaleSupportNormalizesHyphensAndUnderscores() {
  #expect(OnDeviceSpeechPolicy.supports(locale: Locale(identifier: "en-US"),
    supportedLocales: [Locale(identifier: "en_US")]))
  #expect(!OnDeviceSpeechPolicy.supports(locale: Locale(identifier: "en-US"),
    supportedLocales: [Locale(identifier: "en_GB"), Locale(identifier: "fr_US")]))
}

@MainActor @Test func nativeSpeechAvailabilityLossFailsClosed() {
  var failures = 0
  let observer = NativeSpeechAvailabilityObserver { failures += 1 }
  observer.availabilityChanged(true)
  #expect(failures == 0)
  observer.availabilityChanged(false)
  #expect(failures == 1)
}
