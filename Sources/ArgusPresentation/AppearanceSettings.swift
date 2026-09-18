import AppKit
import Observation
import SwiftUI

/// Non-sensitive, local appearance preferences. Invalid input never replaces a valid accent.
@MainActor @Observable
public final class AppearanceSettings {
  public static let presetGreen = "#65C891"
  public static let preferenceKey = "argus.appearance.accentHex"
  public private(set) var hexString: String
  public static let reduceMotionPreferenceKey = "argus.appearance.reduceMotion"
  public private(set) var reduceMotion: Bool

  public func setReduceMotion(_ value: Bool) {
    reduceMotion = value
    defaults.set(value, forKey: Self.reduceMotionPreferenceKey)
  }
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    reduceMotion = defaults.bool(forKey: Self.reduceMotionPreferenceKey)
    hexString = (defaults.object(forKey: Self.preferenceKey) as? String)
      .flatMap(Self.normalizedHex) ?? Self.presetGreen
  }

  public var nsColor: NSColor {
    let rgb = UInt32(hexString.dropFirst(), radix: 16) ?? 0x65C891
    return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
      green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
  }
  public var color: Color { Color(nsColor: nsColor) }

  @discardableResult public func setHex(_ value: String) -> Bool {
    guard let normalized = Self.normalizedHex(value) else { return false }
    hexString = normalized
    defaults.set(normalized, forKey: Self.preferenceKey)
    return true
  }

  private static func normalizedHex(_ value: String) -> String? {
    var digits = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard digits.utf8.count == 6,
      digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
    else { return nil }
    return "#" + digits.uppercased()
  }
}
