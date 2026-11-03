import AppKit
import SwiftUI
import Testing
@testable import ArgusPresentation

struct ArgusColorThemeTests {
  @Test func everySweepStopKeepsTheSelectedHue() {
    for accent in [NSColor(srgbRed: 0.4, green: 0.78, blue: 0.57, alpha: 1),
      NSColor(srgbRed: 0.68, green: 0.61, blue: 0.89, alpha: 1), .systemRed] {
      let base = accent.usingColorSpace(.sRGB)!
      for stop in ActivationPalette.sweepColors(from: accent) {
        let hue = stop.usingColorSpace(.sRGB)!.hueComponent
        let distance = abs(hue - base.hueComponent)
        #expect(min(distance, 1 - distance) < 0.01,
          "A chosen color should not turn into a rainbow")
      }
    }
  }

  @Test func neutralThemesStayNeutralButStillHaveATravellingHighlight() {
    for accent in [NSColor.black, .white, .gray] {
      let stops = ActivationPalette.sweepColors(from: accent).map { $0.usingColorSpace(.sRGB)! }
      #expect(stops.allSatisfy { $0.saturationComponent < 0.01 })
      let brightness = stops.map(\.brightnessComponent)
      #expect(brightness.max()! - brightness.min()! > 0.15)
      #expect(brightness.max()! >= 0.5, "Even a black accent needs a visible highlight")
      #expect(stops.first == stops.last)
    }
  }

  @MainActor @Test func introductionUsesTheExactSummonColors() {
    let accent = Color(nsColor: NSColor(srgbRed: 0.68, green: 0.61, blue: 0.89, alpha: 1))
    let intro = IntroPalette.sweep(accent: accent).map { NSColor($0).usingColorSpace(.sRGB)! }
    let summon = ActivationPalette.sweepColors(from: NSColor(accent)).map { $0.usingColorSpace(.sRGB)! }
    #expect(intro == summon)
  }
}

struct ArgusSurfaceThemeTests {
  // Independent WCAG calculation: removing the ink adjustment must fail this.
  private func luminance(_ color: NSColor) -> CGFloat {
    let c = color.usingColorSpace(.sRGB)!
    func linear(_ value: CGFloat) -> CGFloat {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent)
      + 0.0722 * linear(c.blueComponent)
  }

  @Test func accentTextRemainsReadableOnBothSurfaces() {
    for dark in [false, true] {
      for accent in [NSColor.black, .white, .gray, .red, .green, .blue, .yellow,
        NSColor(srgbRed: 0.4, green: 0.78, blue: 0.57, alpha: 1),
        NSColor(srgbRed: 0.68, green: 0.61, blue: 0.89, alpha: 1)] {
        let theme = ArgusTheme(accent: accent, dark: dark)
        for background in [theme.canvas, theme.panel] {
          let a = luminance(theme.ink), b = luminance(background)
          #expect((max(a, b) + 0.05) / (min(a, b) + 0.05) >= 4.5)
          #expect(background.alphaComponent == 1)
        }
      }
    }
  }

  @Test func changingTheAccentChangesBothSurfaces() {
    for dark in [false, true] {
      let green = ArgusTheme(accent: .green, dark: dark)
      let blue = ArgusTheme(accent: .blue, dark: dark)
      #expect(green.canvas != blue.canvas)
      #expect(green.panel != blue.panel)
      #expect(green.ink != blue.ink)
    }
  }

  @MainActor @Test func savedAccentFeedsTheThemeWithoutChangingThePreference() {
    let name = "ARGUS.ThemeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let appearance = AppearanceSettings(defaults: defaults)
    #expect(appearance.setHex("AD9CE3"))
    let saved = AppearanceSettings(defaults: defaults)
    let light = ArgusTheme(accent: saved.nsColor, dark: false)
    let dark = ArgusTheme(accent: saved.nsColor, dark: true)
    #expect(light.canvas != dark.canvas)
    #expect(saved.hexString == "#AD9CE3")
    #expect(defaults.string(forKey: AppearanceSettings.preferenceKey) == "#AD9CE3")
  }
}
