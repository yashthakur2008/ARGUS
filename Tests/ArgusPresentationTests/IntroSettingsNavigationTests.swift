import Foundation
import Testing
@testable import ArgusPresentation

@MainActor struct IntroSettingsNavigationTests {
  @Test func sidebarSettingsSharesTheAppIntroduction() throws {
    let (model, directory) = try AppModelTests().fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "ARGUS.IntroNavigationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let intro = IntroPresentation(defaults: defaults)
    intro.complete()
    let appearance = AppearanceSettings(defaults: defaults)
    let today = TodayView(model: model, appearance: appearance, intro: intro)

    // This is the SettingsView actually used by TodayView's sidebar route,
    // not a separately constructed stand-in for that destination.
    let settings = today.settingsDestination
    let replay = try #require(settings.intro)
    #expect(replay === intro)
    #expect(settings.appearance === appearance)
    #expect(!intro.isPresented)
    replay.replay()
    #expect(intro.isPresented)
    #expect(!IntroPresentation(defaults: defaults).isPresented,
      "Replaying must not erase the first-run completion preference")
    replay.complete()
    #expect(!intro.isPresented)
  }

  @Test func embeddingWithoutAnIntroductionRemainsSupported() throws {
    let (model, directory) = try AppModelTests().fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(TodayView(model: model).settingsDestination.intro == nil)
  }
}
