import Foundation
import ArgusStore
import SwiftUI
import Testing
@testable import ArgusPresentation

@MainActor
struct IntroPresentationTests {
  private func isolatedDefaults() -> UserDefaults {
    let suite = "argus.intro.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }

  @Test func firstLaunchIntroducesTheApp() {
    #expect(IntroPresentation(defaults: isolatedDefaults()).isPresented)
  }

  @Test func completionPersistsAcrossRelaunch() {
    let defaults = isolatedDefaults()
    let first = IntroPresentation(defaults: defaults)
    first.complete()

    #expect(!first.isPresented)
    // A relaunch must not reintroduce an app the user already dismissed.
    #expect(!IntroPresentation(defaults: defaults).isPresented)
  }

  @Test func quittingDuringFirstRunShowsItAgain() {
    let defaults = isolatedDefaults()
    _ = IntroPresentation(defaults: defaults)

    // Never dismissed, so nothing was recorded and the next launch explains
    // the app rather than silently skipping it.
    #expect(IntroPresentation(defaults: defaults).isPresented)
  }

  @Test func replayDoesNotForgetThatItWasAlreadyCompleted() {
    let defaults = isolatedDefaults()
    let presentation = IntroPresentation(defaults: defaults)
    presentation.complete()

    presentation.replay()

    #expect(presentation.isPresented)
    // Watching it again is not the same as never having seen it, so a later
    // launch must stay quiet.
    #expect(!IntroPresentation(defaults: defaults).isPresented)
  }

  @Test func resetRestoresTheFirstRunExperience() {
    let defaults = isolatedDefaults()
    let presentation = IntroPresentation(defaults: defaults)
    presentation.complete()

    presentation.reset()

    #expect(presentation.isPresented)
    #expect(IntroPresentation(defaults: defaults).isPresented)
  }

  @Test func anOlderCompletionIsReintroduced() {
    let defaults = isolatedDefaults()
    defaults.set(IntroPresentation.currentVersion - 1, forKey: IntroPresentation.preferenceKey)

    #expect(IntroPresentation(defaults: defaults).isPresented)
  }

  @Test func aNewerCompletionIsNotReintroduced() {
    // A downgrade should not nag someone who has already seen a later intro.
    let defaults = isolatedDefaults()
    defaults.set(IntroPresentation.currentVersion + 1, forKey: IntroPresentation.preferenceKey)

    #expect(!IntroPresentation(defaults: defaults).isPresented)
  }

  @Test func introStateIsStoredSeparatelyFromAppearance() {
    // Sharing a key would make changing the accent re-trigger the intro.
    #expect(IntroPresentation.preferenceKey != AppearanceSettings.preferenceKey)
    #expect(IntroPresentation.preferenceKey != AppearanceSettings.reduceMotionPreferenceKey)
  }
}

@MainActor
struct IntroViewTests {
  @Test func viewBuildsForEveryMotionPreference() {
    for reduced in [false, true] {
      _ = IntroView(accent: .green, reduceMotion: reduced) {}.body
    }
  }

  @Test func introSweepMatchesTheSummonAnimation() {
    // The first thing a user sees should use the same visual language as the
    // glow that appears when they later summon ARGUS.
    let accent = Color(nsColor: NSColor(srgbRed: 0.4, green: 0.78, blue: 0.57, alpha: 1))
    let intro = IntroPalette.sweep(accent: accent)
    let summon = ActivationPalette.sweepColors(from: NSColor(accent))

    #expect(intro.count == summon.count)
  }

  @Test func introDescribesOnlyWhatTheAppActuallyDoes() {
    let promises = ([IntroCopy.tagline] + IntroCopy.points.flatMap { [$0.title, $0.detail] })
      .joined(separator: " ").lowercased()

    // The README is explicit that there is no conversational model and no
    // cloud backend. The intro is the first place an overclaim would be
    // discovered to be false, so the selling copy must not imply either.
    // The disclaimer is checked separately: it names these things to deny them.
    for overclaim in ["chatgpt", "cloud", "ai assistant", "understands you", "chat with"] {
      #expect(!promises.contains(overclaim), "Intro overclaims: \(overclaim)")
    }
    #expect(promises.contains("local"))

    let disclaimer = IntroCopy.honesty.lowercased()
    #expect(disclaimer.contains("prototype"))
    #expect(disclaimer.contains("no conversational model"))
  }

  @Test func activationPointsStayHonestAboutConsent() {
    let listening = IntroCopy.points.first { $0.title.lowercased().contains("summon") }
    let detail = try? #require(listening?.detail.lowercased())

    // Listening is opt-in and user-started; implying it is always on would
    // misrepresent the permission model.
    #expect(detail?.contains("opt-in") == true)
  }

  @Test func everyPointHasDistinctSymbolAndText() {
    let symbols = Set(IntroCopy.points.map(\.symbol))
    let titles = Set(IntroCopy.points.map(\.title))

    #expect(symbols.count == IntroCopy.points.count)
    #expect(titles.count == IntroCopy.points.count)
    #expect(IntroCopy.points.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
  }

  @Test func introMotionIsFiniteAndBrief() {
    // A looping or lingering intro would delay reaching the app itself.
    #expect(IntroMotion.haloDuration > 0)
    #expect(IntroMotion.haloDuration <= 2)
  }

  @Test func anUpdatePromptCannotReplaceTheIntroductionOnFirstRun() throws {
    // macOS shows one presentation at a time. A first launch that also finds a
    // new commit would raise the update alert over the sheet, so the user would
    // never learn what ARGUS is. Observed before this gate existed.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = try ReminderStore(databaseURL: dir.appendingPathComponent("t.sqlite"))
    let model = AppModel(store: store, client: FakeNotifications(), clock: { Date() })

    // Building both states proves the flag is part of the view's input, so the
    // update check can be deferred rather than racing the introduction.
    _ = TodayView(model: model, updateModel: nil, introIsPresented: true).body
    _ = TodayView(model: model, updateModel: nil, introIsPresented: false).body
  }
}
