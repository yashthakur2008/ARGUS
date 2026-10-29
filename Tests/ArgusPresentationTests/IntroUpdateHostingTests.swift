import AppKit
import SwiftUI
import Testing
@testable import ArgusPresentation

@MainActor struct IntroUpdateHostingTests {
  @Test(arguments: [IntroReplayTiming.afterCancellation, .rapidDismissal, .beforeViewUpdate])
  private func interruptedIntroCheckCanRunAfterDismissal(timing: IntroReplayTiming) async throws {
    let rapidDismissal = timing == .rapidDismissal
    let delayedViewUpdate = timing == .beforeViewUpdate
    let (model, directory) = try AppModelTests().fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = IntroUpdateFetchGate()
    let updates = GitHubUpdateModel(
      current: { AppUpdateInfo(version: "0.1.18", build: "19", commit: "same", latestEntry: nil) },
      fetch: {
        await withTaskCancellationHandler {
          await gate.fetch()
        } onCancel: {
          Task { await gate.recordCancellation() }
        }
      })
    let suite = "ARGUS.IntroHosting.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let intro = IntroPresentation(defaults: defaults)
    intro.complete()
    let state = HostedIntroState()
    _ = NSApplication.shared
    let host = NSHostingView(rootView: HostedToday(model: model, updates: updates, state: state, intro: intro))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      window.contentView = nil
      window.close()
      Task { await gate.close() }
    }
    host.layoutSubtreeIfNeeded()
    // No ordering front, app launch, native notification client or network.
    try #require(await eventually { await gate.calls == 1 }, "Hosted TodayView must start its real task")
    intro.replay()
    if delayedViewUpdate {
      // The live model changes before SwiftUI replaces the old task input.
      await gate.finish()
      try #require(await eventually { !updates.isChecking })
    }
    state.introIsPresented = true
    try #require(await eventually { state.observedIntro })
    if !delayedViewUpdate {
      try #require(await eventually { await gate.cancellations == 1 }, "Intro transition must cancel the task")
    }
    if rapidDismissal {
      intro.complete()
      state.introIsPresented = false
      try #require(await eventually { !state.observedIntro })
    }
    await gate.finish()
    if !rapidDismissal {
      try #require(await eventually { !updates.isChecking })
      if !delayedViewUpdate { #expect(updates.status == nil) }
      intro.complete()
      state.introIsPresented = false
    }
    #expect(await eventually { await gate.calls == 2 }, "Dismissal must retry the interrupted automatic check")
    await gate.finish()
    #expect(await eventually { updates.status?.kind == .upToDate && !updates.isChecking })
  }

  private func eventually(_ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < deadline {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
  }
}

private enum IntroReplayTiming: Sendable { case afterCancellation, rapidDismissal, beforeViewUpdate }

@MainActor @Observable private final class HostedIntroState {
  var introIsPresented = false
  var observedIntro = false
}

private struct HostedToday: View {
  let model: AppModel
  let updates: GitHubUpdateModel
  let state: HostedIntroState
  let intro: IntroPresentation
  var body: some View {
    TodayView(model: model, updateModel: updates, introIsPresented: state.introIsPresented, intro: intro)
      .onChange(of: state.introIsPresented) { _, value in state.observedIntro = value }
  }
}

private actor IntroUpdateFetchGate {
  var calls = 0
  var cancellations = 0
  private var closed = false
  private var pending: CheckedContinuation<GitHubCommitSnapshot, Never>?
  func fetch() async -> GitHubCommitSnapshot {
    calls += 1
    if closed { return remote }
    return await withCheckedContinuation { pending = $0 }
  }
  private var remote: GitHubCommitSnapshot {
    GitHubCommitSnapshot(sha: "same", htmlURL: URL(string: "https://example.invalid/commit/same")!)
  }
  func close() { closed = true; finish() }
  func recordCancellation() { cancellations += 1 }
  func finish() {
    pending?.resume(returning: remote)
    pending = nil
  }
}
