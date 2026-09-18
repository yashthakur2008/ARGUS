import Foundation
import Testing
@testable import ArgusPlatform

struct ElevenLabsTransportTests {
  private let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/ysswSXp8U9dFpzPJqFje")!

  @Test func statusFailuresContainNoProviderBodyOrCredential() {
    for status in [301, 401, 403, 422, 429, 500] {
      var buffer = ElevenLabsResponseBuffer()
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
      #expect(buffer.accept(response) == .httpStatus(status))
      #expect(buffer.append(Data("private provider error clearly-fake-test-key".utf8)) == .invalidAudio)
      #expect(buffer.data.isEmpty)
      #expect(String(describing: ElevenLabsSpeechFailure.httpStatus(status)) == "httpStatus(\(status))")
    }
  }

  @Test func responseMetadataAndIncrementalBytesAreBounded() {
    var buffer = ElevenLabsResponseBuffer()
    #expect(buffer.accept(URLResponse(url: url, mimeType: "audio/mpeg", expectedContentLength: 1, textEncodingName: nil)) == .invalidResponse)
    #expect(buffer.accept(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!) == .invalidAudio)
    #expect(buffer.accept(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/mpeg", "Content-Length": "1048577"])!) == .responseTooLarge)
    #expect(buffer.accept(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/mpeg"])!) == nil)
    #expect(buffer.append(Data(repeating: 1, count: 1_048_576)) == nil)
    #expect(buffer.append(Data([1])) == .responseTooLarge)
    #expect(buffer.data.count <= 1_048_576)
  }

  @Test func successfulAudioMustBeNonempty() {
    var buffer = ElevenLabsResponseBuffer()
    #expect(buffer.accept(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/mpeg"])!) == nil)
    #expect(buffer.result == .failure(.invalidAudio))
    #expect(buffer.append(Data([1, 2, 3])) == nil)
    #expect(buffer.result == .success(Data([1, 2, 3])))
  }

  @Test @MainActor func unsafeDestinationsFailBeforeCreatingNetworkTask() async {
    let transport = URLSessionElevenLabsTransport()
    for destination in [
      "http://api.elevenlabs.io/v1/text-to-speech/ysswSXp8U9dFpzPJqFje",
      "https://example.invalid/v1/text-to-speech/ysswSXp8U9dFpzPJqFje",
      "https://api.elevenlabs.io:8443/v1/text-to-speech/ysswSXp8U9dFpzPJqFje",
      "https://api.elevenlabs.io/v1/other",
    ] {
      var request = URLRequest(url: URL(string: destination)!)
      request.httpMethod = "POST"
      var results: [Result<Data, ElevenLabsSpeechFailure>] = []
      let token = transport.send(request) { results.append($0) }
      for _ in 0..<20 { await Task.yield() }
      #expect(results == [.failure(.invalidRequest)])
      token.cancel()
    }
  }

  @Test @MainActor func networkErrorsAreRedactedAndCompletionIsExactlyOnce() async {
    var results: [Result<Data, ElevenLabsSpeechFailure>] = []
    let operation = ElevenLabsNetworkOperation { results.append($0) }
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: url) // Never resumed.
    let error = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue,
      userInfo: [NSLocalizedDescriptionKey: "private body clearly-fake-test-key"])
    operation.urlSession(session, task: task, didCompleteWithError: error)
    operation.urlSession(session, task: task, didCompleteWithError: nil)
    operation.cancel()
    for _ in 0..<20 { await Task.yield() }
    #expect(results == [.failure(.timedOut)])
  }

  @Test func urlSessionDelegatePipelineUsesOnlyInterceptedSyntheticResponses() async {
    for (mode, expected) in [
      ("audio", Result<Data, ElevenLabsSpeechFailure>.success(Data([1, 2, 3]))),
      ("status", .failure(.httpStatus(401))),
      ("oversize", .failure(.responseTooLarge)),
      ("empty", .failure(.invalidAudio)),
    ] {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [ElevenLabsURLProtocolStub.self]
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue(mode, forHTTPHeaderField: "X-Test-Mode")
      request.setValue("clearly-fake-test-key", forHTTPHeaderField: "xi-api-key")
      let result = await withCheckedContinuation { continuation in
        let operation = ElevenLabsNetworkOperation { continuation.resume(returning: $0) }
        operation.start(request, configuration: configuration)
      }
      #expect(result == expected)
    }
  }

  @Test func redirectsAreRejectedWithoutForwardingRequest() async {
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let operation = ElevenLabsNetworkOperation { _ in }
    let task = session.dataTask(with: url) // Never resumed.
    let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://example.invalid/"])!
    var redirected = URLRequest(url: URL(string: "https://example.invalid/")!)
    redirected.setValue("clearly-fake-test-key", forHTTPHeaderField: "xi-api-key")
    let forwarded = await withCheckedContinuation { continuation in
      operation.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) {
        continuation.resume(returning: $0)
      }
    }
    #expect(forwarded == nil)
  }
}

/// Intercepts every URL, so these delegate-pipeline tests cannot reach a live API.
private final class ElevenLabsURLProtocolStub: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let mode = request.value(forHTTPHeaderField: "X-Test-Mode")
    let response = HTTPURLResponse(url: request.url!, statusCode: mode == "status" ? 401 : 200,
      httpVersion: nil, headerFields: ["Content-Type": mode == "status" ? "application/json" : "audio/mpeg"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if mode == "oversize" {
      client?.urlProtocol(self, didLoad: Data(repeating: 0, count: 1_048_577))
    } else if mode != "empty" {
      client?.urlProtocol(self, didLoad: Data([1, 2, 3]))
    }
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
