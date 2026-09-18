import AppKit
import Foundation
import Testing
@testable import ArgusPresentation

@MainActor struct AppearanceSettingsTests {
  private func withDefaults(_ body: (UserDefaults) -> Void) {
    let name = "ARGUS.AppearanceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    body(defaults)
  }

  @Test func reduceMotionOverrideDefaultsOffAndPersistsIndependently() {
    withDefaults { defaults in
      let settings = AppearanceSettings(defaults: defaults)
      #expect(!settings.reduceMotion)
      settings.setReduceMotion(true)
      #expect(settings.reduceMotion)
      #expect(AppearanceSettings(defaults: defaults).reduceMotion)
      #expect(settings.hexString == AppearanceSettings.presetGreen)
      settings.setReduceMotion(false)
      #expect(!AppearanceSettings(defaults: defaults).reduceMotion)
    }
  }

  @Test func defaultGreenAndReload() {
    withDefaults { defaults in
      let settings = AppearanceSettings(defaults: defaults)
      #expect(settings.hexString == "#65C891")
      #expect(settings.setHex("  #a1B2c3  "))
      #expect(settings.hexString == "#A1B2C3")
      #expect(AppearanceSettings(defaults: defaults).hexString == "#A1B2C3")
      #expect(abs(settings.nsColor.redComponent - 161.0 / 255) < 0.001)
      #expect(abs(settings.nsColor.greenComponent - 178.0 / 255) < 0.001)
      #expect(abs(settings.nsColor.blueComponent - 195.0 / 255) < 0.001)
    }
  }

  @Test func invalidEditsPreservePreference() {
    withDefaults { defaults in
      let settings = AppearanceSettings(defaults: defaults)
      #expect(settings.setHex("102030"))
      for invalid in ["", "#123", "#12345678", "#GG1122", "12345G", "＃123456"] {
        #expect(!settings.setHex(invalid))
        #expect(settings.hexString == "#102030")
      }
      #expect(AppearanceSettings(defaults: defaults).hexString == "#102030")
    }
  }

  @Test func corruptPreferencesFallBackToGreen() {
    withDefaults { defaults in
      for invalid: Any in ["broken", 42, ["not": "a color"]] {
        defaults.set(invalid, forKey: AppearanceSettings.preferenceKey)
        #expect(AppearanceSettings(defaults: defaults).hexString == AppearanceSettings.presetGreen)
      }
    }
  }
}
