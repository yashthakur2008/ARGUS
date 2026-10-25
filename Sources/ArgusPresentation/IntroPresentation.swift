import Foundation
import Observation

/// Tracks whether the first-run introduction has been seen.
///
/// Persisted locally like other appearance preferences. Completion is recorded
/// only when the user dismisses the intro, so a crash or a forced quit during
/// first run shows it again rather than silently skipping the explanation of
/// what the app does.
@MainActor @Observable
public final class IntroPresentation {
  public static let preferenceKey = "argus.intro.completedVersion"

  /// Bumping this re-introduces the app after a change worth explaining.
  /// Existing users are not interrupted for ordinary releases.
  public static let currentVersion = 1

  public private(set) var isPresented: Bool
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    // A missing key reads as 0, which correctly treats a fresh install as unseen.
    isPresented = defaults.integer(forKey: Self.preferenceKey) < Self.currentVersion
  }

  public func complete() {
    isPresented = false
    defaults.set(Self.currentVersion, forKey: Self.preferenceKey)
  }

  /// Lets a user watch the introduction again without editing defaults by hand.
  public func replay() {
    isPresented = true
  }

  /// Forgets completion so the next launch introduces the app again.
  public func reset() {
    defaults.removeObject(forKey: Self.preferenceKey)
    isPresented = true
  }
}
