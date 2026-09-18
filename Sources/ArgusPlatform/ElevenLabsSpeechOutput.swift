import Foundation

/// Deliberately carries no provider response, request text, key, URL or underlying error.
public enum ElevenLabsSpeechFailure: Error, Sendable, Equatable {
  case disclosureRequired, credentialRequired, emptyText, invalidRequest
  case network, timedOut, httpStatus(Int), redirectRejected
  case invalidResponse, invalidAudio, responseTooLarge, playback
}

/// Implement with secure storage at the composition boundary. Never persist keys in defaults.
@MainActor public protocol ElevenLabsCredentialProvider: AnyObject {
  func apiKey() throws -> String?
}

@MainActor public protocol ElevenLabsRequestCancelling: AnyObject {
  func cancel()
}

@MainActor public protocol ElevenLabsSpeechTransport: AnyObject {
  func send(_ request: URLRequest,
    completion: @escaping @MainActor @Sendable (Result<Data, ElevenLabsSpeechFailure>) -> Void
  ) -> any ElevenLabsRequestCancelling
}

/// Only explicit speak calls send text. The caller must not automatically pass captured
/// transcripts or reminder contents. No speech-recognition or system-voice fallback exists.
@MainActor public final class ElevenLabsSpeechOutput: SpeechOutput {
  public static let voiceID = "ysswSXp8U9dFpzPJqFje"
  public private(set) var isSpeaking = false
  public private(set) var lastFailure: ElevenLabsSpeechFailure?
  public var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?
  public var onFailure: (@MainActor @Sendable (UUID, ElevenLabsSpeechFailure) -> Void)?

  private let credentials: any ElevenLabsCredentialProvider
  private let disclosureAccepted: @MainActor () -> Bool
  private let transport: any ElevenLabsSpeechTransport
  private let playback: any MP3Playback
  private let timeout: Duration
  private var activeID: UUID?
  private var awaitingNetwork = false
  private var request: (any ElevenLabsRequestCancelling)?
  private var watchdog: Task<Void, Never>?

  public init(credentials: any ElevenLabsCredentialProvider,
    disclosureAccepted: @escaping @MainActor () -> Bool,
    transport: any ElevenLabsSpeechTransport = URLSessionElevenLabsTransport(),
    playback: any MP3Playback = NativeMP3Playback(), timeout: Duration = .seconds(30)) {
    self.credentials = credentials
    self.disclosureAccepted = disclosureAccepted
    self.transport = transport
    self.playback = playback
    self.timeout = min(max(timeout, .milliseconds(1)), .seconds(30))
    playback.onCompletion = { [weak self] id, result in
      guard let self, self.activeID == id, !self.awaitingNetwork else { return }
      self.finish(id, result: result, failure: result == .failed ? .playback : nil)
    }
  }

  @discardableResult public func speak(_ text: String) -> UUID {
    stop()
    let id = UUID()
    activeID = id
    lastFailure = nil
    let bounded = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    guard !bounded.isEmpty else { fail(id, .emptyText); return id }
    guard disclosureAccepted() else { fail(id, .disclosureRequired); return id }
    let key: String
    do {
      guard let value = try credentials.apiKey(), !value.isEmpty,
        value.utf8.count <= 512,
        value.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
        fail(id, .credentialRequired); return id
      }
      key = value
    } catch { fail(id, .credentialRequired); return id }
    var urlRequest = URLRequest(url: URL(string:
      "https://api.elevenlabs.io/v1/text-to-speech/\(Self.voiceID)?output_format=mp3_44100_128")!)
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = 20
    urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
    urlRequest.setValue(key, forHTTPHeaderField: "xi-api-key")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
    do {
      urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
        "text": bounded, "model_id": "eleven_multilingual_v2",
        "voice_settings": ["stability": 0.5, "similarity_boost": 0.75,
          "style": 0.0, "use_speaker_boost": true],
      ])
    } catch { fail(id, .invalidRequest); return id }
    isSpeaking = true
    awaitingNetwork = true
    watchdog = Task { @MainActor [weak self, timeout] in
      do { try await Task.sleep(for: timeout) } catch { return }
      self?.fail(id, .timedOut)
    }
    let token = transport.send(urlRequest) { [weak self] result in
      self?.received(result, id: id)
    }
    // Even a synchronously completing injected transport cannot leave a stale token.
    if activeID == id && awaitingNetwork { request = token } else { token.cancel() }
    return id
  }

  public func stop() {
    guard let id = activeID else { return }
    finish(id, result: .cancelled)
  }

  private func received(_ result: Result<Data, ElevenLabsSpeechFailure>, id: UUID) {
    guard activeID == id, awaitingNetwork else { return }
    awaitingNetwork = false
    request = nil
    switch result {
    case .failure(let failure): fail(id, failure)
    case .success(let data):
      guard !data.isEmpty else { fail(id, .invalidAudio); return }
      guard data.count <= ElevenLabsResponseBuffer.maximumBytes else {
        fail(id, .responseTooLarge); return
      }
      do { try playback.play(data, id: id) } catch { fail(id, .playback) }
    }
  }

  private func fail(_ id: UUID, _ failure: ElevenLabsSpeechFailure) {
    finish(id, result: .failed, failure: failure)
  }

  private func finish(_ id: UUID, result: SpeechOutputResult,
    failure: ElevenLabsSpeechFailure? = nil) {
    guard activeID == id else { return }
    activeID = nil
    awaitingNetwork = false
    isSpeaking = false
    lastFailure = failure
    watchdog?.cancel()
    watchdog = nil
    let token = request
    request = nil
    token?.cancel()
    playback.stop()
    let completion = onCompletion
    let failureCompletion = onFailure
    Task { @MainActor in
      if let failure { failureCompletion?(id, failure) }
      completion?(id, result)
    }
  }
}
