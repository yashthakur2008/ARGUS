import AppKit

/// Derived colors, never additional preferences. Native primary/secondary text
/// and semantic warning colors remain untouched by the user's accent choice.
struct ArgusTheme {
  let canvas: NSColor
  let panel: NSColor
  let ink: NSColor

  init(accent: NSColor, dark: Bool) {
    let base = accent.usingColorSpace(.sRGB) ?? .gray
    let canvasBase = NSColor(srgbRed: dark ? 0.075 : 0.96,
      green: dark ? 0.075 : 0.96, blue: dark ? 0.075 : 0.96, alpha: 1)
    let panelBase = NSColor(srgbRed: dark ? 0.12 : 1,
      green: dark ? 0.12 : 1, blue: dark ? 0.12 : 1, alpha: 1)
    canvas = Self.mix(canvasBase, base, amount: dark ? 0.07 : 0.065)
    panel = Self.mix(panelBase, base, amount: dark ? 0.08 : 0.025)
    // Move only as far toward white/black as needed for readable accent text.
    // Both themed surfaces are tested, since cards differ from the canvas.
    let target = NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0,
      blue: dark ? 1 : 0, alpha: 1)
    var readable = base
    for step in 0...100 {
      readable = Self.mix(base, target, amount: CGFloat(step) / 100)
      if Self.contrast(readable, canvas) >= 4.5 && Self.contrast(readable, panel) >= 4.5 { break }
    }
    ink = readable
  }

  private static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
    func luminance(_ c: NSColor) -> CGFloat {
      func linear(_ v: CGFloat) -> CGFloat {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent)
        + 0.0722 * linear(c.blueComponent)
    }
    let x = luminance(a), y = luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
  }

  private static func mix(_ a: NSColor, _ b: NSColor, amount: CGFloat) -> NSColor {
    NSColor(srgbRed: a.redComponent * (1 - amount) + b.redComponent * amount,
      green: a.greenComponent * (1 - amount) + b.greenComponent * amount,
      blue: a.blueComponent * (1 - amount) + b.blueComponent * amount, alpha: 1)
  }
}
