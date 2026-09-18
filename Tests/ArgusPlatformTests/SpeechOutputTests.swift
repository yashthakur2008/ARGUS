import Foundation
import Testing
@testable import ArgusPlatform

@MainActor struct SpeechOutputTests {
  @Test func initializationAndStopNeverCreateDriver() {
    var creations = 0
    let output = NativeSpeechOutput(makeDriver: { creations += 1; return SpeechDriverFake() })
    #expect(!output.isSpeaking)
    output.stop()
    #expect(creations == 0)
  }

  @Test func textIsBoundedAndSupersededCallbacksCannotFinishCurrentRequest() async {
    let driver = SpeechDriverFake()
    let output = NativeSpeechOutput(makeDriver: { driver })
    var results: [SpeechOutputResult] = []
    output.onCompletion = { _, result in results.append(result) }
    let first = output.speak(String(repeating: "a", count: 500))
    #expect(driver.texts.first?.count == 160)
    let second = output.speak("Second")
    #expect(first != second)
    #expect(driver.stops == 1)
    driver.onCompletion?(first, .finished)
    #expect(output.isSpeaking)
    driver.onCompletion?(second, .finished)
    for _ in 0..<10 { await Task.yield() }
    #expect(!output.isSpeaking)
    #expect(results.filter { $0 == .finished }.count == 1)
    #expect(results.filter { $0 == .cancelled }.count == 1)
  }

  @Test func emptyTextAndUnavailableVoiceFailWithoutSpeaking() async {
    let driver = SpeechDriverFake()
    let output = NativeSpeechOutput(makeDriver: { driver })
    var results: [SpeechOutputResult] = []
    output.onCompletion = { _, result in results.append(result) }
    output.speak(" \n ")
    for _ in 0..<10 { await Task.yield() }
    #expect(driver.texts.isEmpty)
    #expect(results == [.failed])
    driver.fails = true
    output.speak("Hello")
    for _ in 0..<10 { await Task.yield() }
    #expect(results == [.failed, .failed])
    #expect(!output.isSpeaking)
  }

  @Test func explicitStopReportsCancellationOnlyOnce() async {
    let driver = SpeechDriverFake()
    let output = NativeSpeechOutput(makeDriver: { driver })
    var results: [SpeechOutputResult] = []
    output.onCompletion = { _, result in results.append(result) }
    let id = output.speak("Hello")
    output.stop()
    driver.onCompletion?(id, .cancelled)
    driver.onCompletion?(id, .finished)
    for _ in 0..<10 { await Task.yield() }
    #expect(results == [.cancelled])
    #expect(!output.isSpeaking)
  }
}

@MainActor private final class SpeechDriverFake: LocalSpeechSynthesisDriver {
  var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?
  var texts: [String] = []
  var stops = 0
  var fails = false
  func speak(_ text: String, id: UUID) throws {
    if fails { throw NSError(domain: "test", code: 1) }
    texts.append(text)
  }
  func stop() { stops += 1 }
}
