import Foundation
import Testing
@testable import ArgusPlatform

@MainActor struct ElevenLabsSpeechOutputTests {
  @Test func requestUsesFixedVoiceFakeCredentialAndBoundedText() throws {
    let transport = ElevenTransportFake()
    let output = makeOutput(transport: transport)
    output.speak("  " + String(repeating: "a", count: 200) + "\n")
    let request = try #require(transport.requests.first)
    #expect(request.url?.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/ysswSXp8U9dFpzPJqFje?output_format=mp3_44100_128")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "xi-api-key") == "clearly-fake-test-key")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Accept") == "audio/mpeg")
    #expect(request.timeoutInterval == 20)
    let bodyData = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
    #expect(body["text"] as? String == String(repeating: "a", count: 160))
    #expect(body["model_id"] as? String == "eleven_multilingual_v2")
    let settings = try #require(body["voice_settings"] as? [String: Any])
    #expect(settings["stability"] as? Double == 0.5)
    #expect(settings["similarity_boost"] as? Double == 0.75)
    #expect(settings["style"] as? Double == 0)
    #expect(settings["use_speaker_boost"] as? Bool == true)
    output.stop()
  }

  @Test func consentAndKeyAreMandatoryAndCompletionIsDeferred() async {
    let transport = ElevenTransportFake()
    let credentials = ElevenCredentialsFake()
    var consent = false
    let output = ElevenLabsSpeechOutput(credentials: credentials, disclosureAccepted: { consent }, transport: transport, playback: MP3Fake())
    var failures: [ElevenLabsSpeechFailure] = []
    var results: [SpeechOutputResult] = []
    output.onFailure = { _, failure in failures.append(failure) }
    output.onCompletion = { _, result in results.append(result) }
    output.speak("Hello")
    #expect(results.isEmpty)
    #expect(credentials.reads == 0)
    await drain()
    #expect(failures == [.disclosureRequired])
    consent = true
    credentials.key = nil
    output.speak("Hello")
    await drain()
    #expect(failures == [.disclosureRequired, .credentialRequired])
    #expect(results == [.failed, .failed])
    #expect(transport.requests.isEmpty)
    #expect(output.lastFailure == .credentialRequired)
  }

  @Test func emptyTextAndCredentialErrorsDoNotSendRequests() async {
    let transport = ElevenTransportFake()
    let credentials = ElevenCredentialsFake()
    let output = ElevenLabsSpeechOutput(credentials: credentials, disclosureAccepted: { true }, transport: transport, playback: MP3Fake())
    output.speak(" \n ")
    #expect(output.lastFailure == .emptyText)
    credentials.fails = true
    output.speak("Hello")
    #expect(output.lastFailure == .credentialRequired)
    #expect(transport.requests.isEmpty)
    await drain()
  }

  @Test func cancellationRejectsLateNetworkAndPlaybackCallbacks() async {
    let transport = ElevenTransportFake()
    let playback = MP3Fake()
    let output = makeOutput(transport: transport, playback: playback)
    var events: [(UUID, SpeechOutputResult)] = []
    output.onCompletion = { events.append(($0, $1)) }
    let first = output.speak("First")
    let second = output.speak("Second")
    #expect(transport.tokens[0].cancelled)
    transport.completions[0](.success(Data([1])))
    #expect(playback.ids.isEmpty)
    transport.completions[1](.success(Data([1])))
    #expect(playback.ids == [second])
    playback.onCompletion?(first, .finished)
    #expect(output.isSpeaking)
    output.stop()
    playback.onCompletion?(second, .finished)
    transport.completions[1](.failure(.network))
    await drain()
    #expect(events.count == 2)
    #expect(events.allSatisfy { $0.1 == .cancelled })
    #expect(!output.isSpeaking)
  }

  @Test func actualPlaybackCompletionIsRequiredAndFailuresAreTyped() async {
    let transport = ElevenTransportFake()
    let playback = MP3Fake()
    let output = makeOutput(transport: transport, playback: playback)
    var results: [SpeechOutputResult] = []
    output.onCompletion = { _, result in results.append(result) }
    let id = output.speak("Hello")
    transport.completions[0](.success(Data([1])))
    await drain()
    #expect(results.isEmpty)
    #expect(output.isSpeaking)
    playback.onCompletion?(id, .finished)
    await drain()
    #expect(results == [.finished])
    playback.fails = true
    output.speak("Again")
    transport.completions[1](.success(Data([1])))
    await drain()
    #expect(results == [.finished, .failed])
    #expect(output.lastFailure == .playback)
  }

  @Test func timeoutCancelsAndNeverReportsSuccess() async throws {
    let transport = ElevenTransportFake()
    let output = ElevenLabsSpeechOutput(credentials: ElevenCredentialsFake(), disclosureAccepted: { true }, transport: transport, playback: MP3Fake(), timeout: .milliseconds(5))
    var results: [SpeechOutputResult] = []
    output.onCompletion = { _, result in results.append(result) }
    output.speak("Hello")
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while results.isEmpty && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(output.lastFailure == .timedOut)
    #expect(transport.tokens[0].cancelled)
    #expect(results == [.failed])
    transport.completions[0](.success(Data([1])))
    await drain()
    #expect(results == [.failed])
  }

  @Test func injectedTransportCannotBypassAudioBounds() {
    let transport = ElevenTransportFake()
    let playback = MP3Fake()
    let output = makeOutput(transport: transport, playback: playback)
    output.speak("Hello")
    transport.completions[0](.success(Data()))
    #expect(output.lastFailure == .invalidAudio)
    output.speak("Hello")
    transport.completions[1](.success(Data(repeating: 0, count: 1_048_577)))
    #expect(output.lastFailure == .responseTooLarge)
    #expect(playback.ids.isEmpty)
  }

  @Test func initializationDoesNotReadCredentialsOrRequestAudio() {
    let credentials = ElevenCredentialsFake()
    let transport = ElevenTransportFake()
    let output = ElevenLabsSpeechOutput(credentials: credentials, disclosureAccepted: { true }, transport: transport, playback: MP3Fake())
    output.stop()
    #expect(credentials.reads == 0)
    #expect(transport.requests.isEmpty)
    #expect(!output.isSpeaking)
  }

  @Test func malformedKeysCannotBecomeHeaders() {
    let credentials = ElevenCredentialsFake()
    let transport = ElevenTransportFake()
    let output = ElevenLabsSpeechOutput(credentials: credentials, disclosureAccepted: { true }, transport: transport, playback: MP3Fake())
    for key in ["", " ", "clearly-fake\r\nheader", String(repeating: "x", count: 513)] {
      credentials.key = key
      output.speak("Hello")
      #expect(output.lastFailure == .credentialRequired)
    }
    #expect(transport.requests.isEmpty)
  }

  @Test func duplicateNetworkCompletionCannotRestartPlayback() {
    let transport = ElevenTransportFake()
    let playback = MP3Fake()
    let output = makeOutput(transport: transport, playback: playback)
    let id = output.speak("Hello")
    transport.completions[0](.success(Data([1])))
    transport.completions[0](.success(Data([2])))
    transport.completions[0](.failure(.network))
    #expect(playback.ids == [id])
    #expect(output.isSpeaking)
    output.stop()
  }

  @Test func playbackTimeoutStopsAudioAndIgnoresLateFinish() async throws {
    let transport = ElevenTransportFake()
    let playback = MP3Fake()
    let output = ElevenLabsSpeechOutput(credentials: ElevenCredentialsFake(), disclosureAccepted: { true }, transport: transport, playback: playback, timeout: .milliseconds(5))
    var results: [SpeechOutputResult] = []
    output.onCompletion = { _, result in results.append(result) }
    let id = output.speak("Hello")
    transport.completions[0](.success(Data([1])))
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while results.isEmpty && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(playback.stops == 1)
    #expect(output.lastFailure == .timedOut)
    playback.onCompletion?(id, .finished)
    await drain()
    #expect(results == [.failed])
  }

  @Test func nativePlaybackRejectsEmptyAndOversizedDataWithoutAudio() {
    let playback = NativeMP3Playback()
    #expect(throws: ElevenLabsSpeechFailure.invalidAudio) {
      try playback.play(Data(), id: UUID())
    }
    #expect(throws: ElevenLabsSpeechFailure.invalidAudio) {
      try playback.play(Data(repeating: 0, count: 1_048_577), id: UUID())
    }
    playback.stop()
  }

  private func makeOutput(transport: ElevenTransportFake, playback: MP3Fake = MP3Fake()) -> ElevenLabsSpeechOutput {
    ElevenLabsSpeechOutput(credentials: ElevenCredentialsFake(), disclosureAccepted: { true }, transport: transport, playback: playback)
  }
  private func drain() async { for _ in 0..<20 { await Task.yield() } }
}

@MainActor private final class ElevenCredentialsFake: ElevenLabsCredentialProvider {
  var key: String? = "clearly-fake-test-key"
  var reads = 0
  var fails = false
  func apiKey() throws -> String? {
    reads += 1
    if fails { throw NSError(domain: "redacted-test-error", code: 1) }
    return key
  }
}
@MainActor private final class ElevenCancelFake: ElevenLabsRequestCancelling {
  var cancelled = false
  func cancel() { cancelled = true }
}
@MainActor private final class ElevenTransportFake: ElevenLabsSpeechTransport {
  var requests: [URLRequest] = []
  var completions: [@MainActor @Sendable (Result<Data, ElevenLabsSpeechFailure>) -> Void] = []
  var tokens: [ElevenCancelFake] = []
  func send(_ request: URLRequest, completion: @escaping @MainActor @Sendable (Result<Data, ElevenLabsSpeechFailure>) -> Void) -> any ElevenLabsRequestCancelling {
    requests.append(request)
    completions.append(completion)
    let token = ElevenCancelFake()
    tokens.append(token)
    return token
  }
}
@MainActor private final class MP3Fake: MP3Playback {
  var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?
  var ids: [UUID] = []
  var fails = false
  var stops = 0
  func play(_ data: Data, id: UUID) throws {
    if fails { throw NSError(domain: "redacted-test-error", code: 1) }
    ids.append(id)
  }
  func stop() { stops += 1 }
}
