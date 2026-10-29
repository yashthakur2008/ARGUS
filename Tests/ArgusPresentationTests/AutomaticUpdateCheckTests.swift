import Foundation
import Testing
@testable import ArgusPresentation

@MainActor struct AutomaticUpdateCheckTests {
  @Test(arguments: [false, true])
  func pendingSettingsResultIsSharedWithoutAnotherFetch(offline: Bool) async {
    let gate = AutomaticFetchGate()
    let model = makeModel(gate)
    let settings = Task { await model.check() }
    await gate.waitUntilStarted()
    var entered = false
    var finished = false
    let automatic = Task {
      entered = true
      await model.checkWhenAvailable()
      finished = true
    }
    while !entered { await Task.yield() }
    #expect(!finished, "Automatic prompting must wait, not consume a busy model as completion")
    await gate.finish(offline: offline)
    await settings.value
    await automatic.value
    #expect(await gate.calls == 1)
    #expect(finished)
    if offline {
      #expect(model.errorMessage != nil)
      #expect(model.status == nil)
    } else {
      #expect(model.status?.showsUpdatePrompt == true)
    }
  }

  @Test func activeWaiterRetriesAfterOwnerCancellation() async {
    let gate = AutomaticFetchGate()
    let model = makeModel(gate)
    let owner = Task { await model.check() }
    await gate.waitUntilStarted()
    var entered = false
    let waiter = Task { entered = true; await model.checkWhenAvailable() }
    while !entered { await Task.yield() }
    owner.cancel()
    await gate.finish()
    await owner.value
    await waiter.value
    #expect(await gate.calls == 2)
    #expect(model.status?.showsUpdatePrompt == true)
  }

  @Test func cancelledWaiterDoesNotStartAnotherFetch() async {
    let gate = AutomaticFetchGate()
    let model = makeModel(gate)
    let owner = Task { await model.check() }
    await gate.waitUntilStarted()
    var entered = false
    let waiter = Task { entered = true; await model.checkWhenAvailable() }
    while !entered { await Task.yield() }
    waiter.cancel()
    owner.cancel()
    await gate.finish()
    await owner.value
    await waiter.value
    #expect(await gate.calls == 1)
    #expect(model.status == nil)
    #expect(!model.isChecking)
  }

  @Test func cancelledWaiterFinishesWhileOwnerIsStillSuspended() async {
    let gate = AutomaticFetchGate()
    let model = makeModel(gate)
    let owner = Task { await model.check() }
    await gate.waitUntilStarted()
    var entered = false
    var finished = false
    let waiter = Task {
      entered = true
      await model.checkWhenAvailable()
      finished = true
    }
    while !entered { await Task.yield() }
    waiter.cancel()
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !finished && ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(finished, "Cancelled presentation must not remain retained by the owner's fetch")
    #expect(model.isChecking)
    #expect(await gate.calls == 1)
    await gate.finish()
    await owner.value
    await waiter.value
  }

  private func makeModel(_ gate: AutomaticFetchGate) -> GitHubUpdateModel {
    GitHubUpdateModel(
      current: { AppUpdateInfo(version: "0.1.18", build: "19", commit: "old", latestEntry: nil) },
      fetch: { try await gate.fetch() })
  }
}

private actor AutomaticFetchGate {
  var calls = 0
  private var pending: CheckedContinuation<GitHubCommitSnapshot, any Error>?
  private var started: CheckedContinuation<Void, Never>?
  private let remote = GitHubCommitSnapshot(sha: "new",
    htmlURL: URL(string: "https://example.invalid/commit/new")!)

  func fetch() async throws -> GitHubCommitSnapshot {
    calls += 1
    if calls > 1 { return remote }
    return try await withCheckedThrowingContinuation {
      pending = $0
      started?.resume()
      started = nil
    }
  }

  func waitUntilStarted() async {
    if pending != nil { return }
    await withCheckedContinuation { started = $0 }
  }

  func finish(offline: Bool = false) {
    if offline { pending?.resume(throwing: URLError(.notConnectedToInternet)) }
    else { pending?.resume(returning: remote) }
    pending = nil
  }
}
