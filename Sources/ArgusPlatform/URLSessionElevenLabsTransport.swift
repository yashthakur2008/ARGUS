import Foundation

/// Ephemeral, uncached, cookie-free, bounded HTTPS requests with redirects always rejected.
@MainActor public final class URLSessionElevenLabsTransport: ElevenLabsSpeechTransport {
  public init() {}

  public func send(_ request: URLRequest,
    completion: @escaping @MainActor @Sendable (Result<Data, ElevenLabsSpeechFailure>) -> Void
  ) -> any ElevenLabsRequestCancelling {
    let operation = ElevenLabsNetworkOperation(completion: completion)
    guard let url = request.url, url.scheme == "https", url.host == "api.elevenlabs.io",
      url.port == nil || url.port == 443, url.user == nil, url.password == nil,
      url.path == "/v1/text-to-speech/\(ElevenLabsSpeechOutput.voiceID)",
      request.httpMethod == "POST" else {
      operation.complete(.failure(.invalidRequest))
      return ElevenLabsNetworkCancellation(operation)
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 25
    configuration.waitsForConnectivity = false
    operation.start(request, configuration: configuration)
    return ElevenLabsNetworkCancellation(operation)
  }
}

@MainActor private final class ElevenLabsNetworkCancellation: ElevenLabsRequestCancelling {
  private let operation: ElevenLabsNetworkOperation
  init(_ operation: ElevenLabsNetworkOperation) { self.operation = operation }
  func cancel() { operation.cancel() }
  deinit { operation.cancel() }
}

/// The delegate queue is serial, but cancellation can arrive from the main actor.
/// All mutable state is guarded by lock. No callbacks or session calls run under lock.
final class ElevenLabsNetworkOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var buffer = ElevenLabsResponseBuffer()
  private var session: URLSession?
  private var completion: (@MainActor @Sendable (Result<Data, ElevenLabsSpeechFailure>) -> Void)?

  init(completion: @escaping @MainActor @Sendable (Result<Data, ElevenLabsSpeechFailure>) -> Void) {
    self.completion = completion
  }

  func start(_ request: URLRequest, configuration: URLSessionConfiguration) {
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    lock.withLock { self.session = session }
    session.dataTask(with: request).resume()
  }

  func cancel() { complete(.failure(.network)) }

  func complete(_ result: Result<Data, ElevenLabsSpeechFailure>) {
    let state = lock.withLock {
      let state = (completion, session)
      completion = nil
      session = nil
      buffer = ElevenLabsResponseBuffer()
      return state
    }
    state.1?.invalidateAndCancel()
    if let completion = state.0 { Task { @MainActor in completion(result) } }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
    let failure = lock.withLock { buffer.accept(response) }
    completionHandler(failure == nil ? .allow : .cancel)
    if let failure { complete(.failure(failure)) }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    let failure = lock.withLock { buffer.append(data) }
    if let failure { complete(.failure(failure)) }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
    didCompleteWithError error: (any Error)?) {
    if let error {
      complete(.failure((error as? URLError)?.code == .timedOut ? .timedOut : .network))
    } else {
      complete(lock.withLock { buffer.result })
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
    // Reject even same-origin redirects, never forward xi-api-key or text elsewhere.
    completionHandler(nil)
    complete(.failure(.redirectRejected))
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
    willCacheResponse proposedResponse: CachedURLResponse,
    completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void) {
    completionHandler(nil)
  }
}

struct ElevenLabsResponseBuffer {
  static let maximumBytes = 1_048_576
  private(set) var data = Data()
  private var accepted = false

  mutating func accept(_ response: URLResponse) -> ElevenLabsSpeechFailure? {
    accepted = false
    data = Data()
    guard let response = response as? HTTPURLResponse else { return .invalidResponse }
    guard response.statusCode == 200 else { return .httpStatus(response.statusCode) }
    guard ["audio/mpeg", "audio/mp3"].contains(response.mimeType?.lowercased() ?? "") else {
      return .invalidAudio
    }
    guard response.expectedContentLength <= Self.maximumBytes else { return .responseTooLarge }
    accepted = true
    return nil
  }

  mutating func append(_ chunk: Data) -> ElevenLabsSpeechFailure? {
    guard accepted else { return .invalidAudio }
    guard chunk.count <= Self.maximumBytes - data.count else {
      accepted = false
      data = Data()
      return .responseTooLarge
    }
    data.append(chunk)
    return nil
  }

  var result: Result<Data, ElevenLabsSpeechFailure> {
    accepted && !data.isEmpty ? .success(data) : .failure(.invalidAudio)
  }
}
