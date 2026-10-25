import AppKit
import SwiftUI
import Testing
@testable import ArgusPresentation

@MainActor struct ThemeRenderingTests {
  @Test func introductionRendersTheSelectedThemeInLightAndDark() throws {
    for (name, accent) in [
      ("green", NSColor(srgbRed: 0.396, green: 0.784, blue: 0.569, alpha: 1)),
      ("lavender", NSColor(srgbRed: 0.678, green: 0.612, blue: 0.89, alpha: 1))
    ] {
      for dark in [false, true] {
        let theme = ArgusTheme(accent: accent, dark: dark)
        let view = IntroView(accent: Color(nsColor: accent), reduceMotion: true) {}
          .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect(bitmap.pixelsWide >= 520)
        #expect(bitmap.pixelsHigh >= 500)
        // The corner belongs to the actual view background, not a test swatch.
        // colorAt returns these bitmap components tagged as generic RGB on
        // macOS. Converting that NSColor would transform sRGB samples twice.
        #expect(bitmap.colorSpace == NSColorSpace.sRGB)
        let pixel = try #require(bitmap.colorAt(x: 4, y: 4))
        #expect(abs(pixel.redComponent - theme.canvas.redComponent) < 0.02)
        #expect(abs(pixel.greenComponent - theme.canvas.greenComponent) < 0.02)
        #expect(abs(pixel.blueComponent - theme.canvas.blueComponent) < 0.02)
        if let directory = ProcessInfo.processInfo.environment["ARGUS_THEME_CAPTURES"] {
          let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("intro-\(name)-\(dark ? "dark" : "light").png")
          let png = try #require(bitmap.representation(using: .png, properties: [:]))
          try png.write(to: url)
        }
      }
    }
  }
}
