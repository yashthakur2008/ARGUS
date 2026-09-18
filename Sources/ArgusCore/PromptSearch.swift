import Foundation

public enum PromptSearchNormalization {
  /// Version 1: NFC, fixed-locale case folding only, then NFC again.
  public static func v1(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping
      .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .precomposedStringWithCanonicalMapping
  }
}
