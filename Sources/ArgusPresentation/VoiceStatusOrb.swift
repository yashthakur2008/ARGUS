import SwiftUI

/// Status only, never an audio meter. No capture, repeating animation, or idle renderer.
public struct VoiceStatusOrb: View {
  public enum State: Equatable, Sendable {
    case off, listening, speaking

    public var label: String {
      switch self {
      case .off: "Voice off"
      case .listening: "Listening"
      case .speaking: "Speaking"
      }
    }

    fileprivate var symbol: String {
      switch self {
      case .off: "mic.slash.fill"
      case .listening: "mic.fill"
      case .speaking: "speaker.wave.2.fill"
      }
    }
  }

  private let state: State
  private let accent: Color
  private let reduceMotion: Bool
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  public init(state: State, accent: Color, reduceMotion: Bool = false) {
    self.state = state
    self.accent = accent
    self.reduceMotion = reduceMotion
  }

  public var body: some View {
    let motionReduced = systemReduceMotion || reduceMotion
    HStack(spacing: 9) {
      ZStack {
        Circle()
          .fill(RadialGradient(colors: [.white.opacity(0.75), accent, accent.opacity(0.35)],
            center: .topLeading, startRadius: 0, endRadius: 31))
          .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.75))
          .shadow(color: accent.opacity(state == .off ? 0 : 0.24), radius: 5)
          .opacity(state == .off ? 0.35 : 1)
        Image(systemName: state.symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.primary)
      }
      .frame(width: 30, height: 30)
      Text(state.label)
        .font(.callout.weight(.medium))
        .foregroundStyle(state == .off ? .secondary : .primary)
    }
    .animation(motionReduced ? nil : .easeOut(duration: 0.18), value: state)
    // Recreate the subtree when motion policy changes to cancel an in-flight transition.
    .id(motionReduced)
    .transaction { if motionReduced { $0.animation = nil; $0.disablesAnimations = true } }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(state.label)
  }
}
