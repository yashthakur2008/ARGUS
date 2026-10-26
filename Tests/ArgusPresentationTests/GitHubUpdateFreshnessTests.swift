import Foundation
import Testing
@testable import ArgusPresentation

@MainActor struct GitHubUpdateFreshnessTests {
  private let current = AppUpdateInfo(version: "0.1.18", build: "19", commit: "old", latestEntry: nil)
  private let remote = GitHubCommitSnapshot(sha: "new",
    htmlURL: URL(string: "https://github.com/yashthakur2008/ARGUS/commit/new")!)

  @Test func failedRefreshCannotPresentThePreviousUpdate() async {
    let fetch = UpdateFetchSequence(remote: remote, failure: .offline)
    let model = GitHubUpdateModel(current: { current }, fetch: { try await fetch.next() })
    await model.check()
    #expect(model.status?.showsUpdatePrompt == true)
    await model.check()
    #expect(model.status == nil, "A failed check must not leave an old result eligible for prompting")
    #expect(model.errorMessage != nil)
    #expect(!model.isChecking)
    await model.check()
    #expect(model.status?.latestCommit == "new")
    #expect(model.errorMessage == nil)
  }

  @Test(arguments: [UpdateFetchSequence.Failure.cancelled, .urlCancelled])
  private func cancelledRefreshIsNotAnOfflineError(_ failure: UpdateFetchSequence.Failure) async {
    let fetch = UpdateFetchSequence(remote: remote, failure: failure)
    let model = GitHubUpdateModel(current: { current }, fetch: { try await fetch.next() })
    await model.check()
    await model.check()
    #expect(model.status == nil)
    #expect(model.errorMessage == nil)
    #expect(!model.isChecking)
  }

  @Test func cancelledCallerCannotPublishALateSuccessfulFetch() async {
    let gate = SuspendedCommitFetch(remote: remote)
    let model = GitHubUpdateModel(current: { current }, fetch: { await gate.fetch() })
    let check = Task { await model.check() }
    await gate.waitUntilStarted()
    #expect(model.isChecking)
    check.cancel()
    await gate.finish()
    await check.value
    #expect(model.status == nil)
    #expect(model.errorMessage == nil)
    #expect(!model.isChecking)
  }

  @Test func aConcurrentCallerCannotReadThePreviousCheckAsFresh() async {
    let gate = SuspendedCommitFetch(remote: remote, initial: remote)
    let model = GitHubUpdateModel(current: { current }, fetch: { await gate.fetch() })
    await model.check()
    #expect(model.status != nil)
    let refresh = Task { await model.check() }
    await gate.waitUntilStarted()
    #expect(model.isChecking)
    #expect(model.status == nil)
    // A second caller returns without owning the in-flight request. It must
    // not mistake the previous result for completion of this refresh.
    await model.check()
    #expect(model.status == nil)
    #expect(model.isChecking)
    await gate.finish()
    await refresh.value
    #expect(model.status?.latestCommit == "new")
    #expect(!model.isChecking)
  }
}

private actor UpdateFetchSequence {
  enum Failure: Sendable { case offline, cancelled, urlCancelled }
  let remote: GitHubCommitSnapshot
  let failure: Failure
  var calls = 0
  init(remote: GitHubCommitSnapshot, failure: Failure) { self.remote = remote; self.failure = failure }
  func next() throws -> GitHubCommitSnapshot {
    calls += 1
    if calls == 2 {
      switch failure {
      case .offline: throw URLError(.notConnectedToInternet)
      case .cancelled: throw CancellationError()
      case .urlCancelled: throw URLError(.cancelled)
      }
    }
    return remote
  }
}

private actor SuspendedCommitFetch {
  let remote: GitHubCommitSnapshot
  var initial: GitHubCommitSnapshot?
  var pending: CheckedContinuation<GitHubCommitSnapshot, Never>?
  var started: CheckedContinuation<Void, Never>?
  init(remote: GitHubCommitSnapshot, initial: GitHubCommitSnapshot? = nil) {
    self.remote = remote
    self.initial = initial
  }
  func fetch() async -> GitHubCommitSnapshot {
    if let initial {
      self.initial = nil
      return initial
    }
    return await withCheckedContinuation { continuation in
      pending = continuation
      started?.resume()
      started = nil
    }
  }
  func waitUntilStarted() async {
    if pending != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func finish() {
    pending?.resume(returning: remote)
    pending = nil
  }
}
