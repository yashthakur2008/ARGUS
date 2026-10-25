import SwiftUI

/// First-run introduction.
///
/// Shown once, modally over the Today view, then never again unless the user
/// resets it. It introduces the app and nothing else: it requests no
/// permissions, starts no capture, and creates no reminders, so dismissing it
/// cannot leave the app in a state the user did not choose.
public struct IntroView: View {
  private let accent: Color
  private let reduceMotion: Bool
  private let onContinue: () -> Void
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @State private var phase: CGFloat = 0
  @State private var revealed = false

  public init(accent: Color, reduceMotion: Bool = false, onContinue: @escaping () -> Void) {
    self.accent = accent
    self.reduceMotion = reduceMotion
    self.onContinue = onContinue
  }

  private var motionReduced: Bool { systemReduceMotion || reduceMotion }

  public var body: some View {
    VStack(spacing: 24) {
      IntroHaloView(accent: accent, phase: phase, motionReduced: motionReduced)
        .frame(width: 132, height: 132)
        .padding(.top, 8)

      VStack(spacing: 10) {
        Text("ARGUS")
          .font(.system(size: 34, weight: .semibold, design: .rounded))
          .kerning(6)
          .foregroundStyle(IntroPalette.titleGradient(accent: accent))
        Text(IntroCopy.tagline)
          .font(.title3)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          // Without an explicit line limit the tagline truncates to a single
          // line with an ellipsis instead of wrapping onto two.
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 420)
      }

      VStack(alignment: .leading, spacing: 14) {
        ForEach(Array(IntroCopy.points.enumerated()), id: \.offset) { index, point in
          IntroPointRow(point: point, accent: accent)
            .opacity(revealed || motionReduced ? 1 : 0)
            .offset(y: revealed || motionReduced ? 0 : 8)
            .animation(
              motionReduced ? nil
                : .easeOut(duration: 0.34).delay(0.18 + Double(index) * 0.08),
              value: revealed)
        }
      }
      .frame(maxWidth: 420, alignment: .leading)

      Text(IntroCopy.honesty)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        // The disclaimer is the one line that must never be cut off, so it
        // wraps instead of truncating to an ellipsis.
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 420)

      Button(action: onContinue) {
        Text("Get started").frame(maxWidth: 200)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .tint(accent)
      .keyboardShortcut(.defaultAction)
    }
    .padding(40)
    .frame(minWidth: 520)
    .task {
      guard !motionReduced else { return }
      // A single finite pass. The halo settles instead of looping forever,
      // matching the activation glow's one-shot behaviour.
      withAnimation(.easeInOut(duration: IntroMotion.haloDuration)) { phase = 1 }
      revealed = true
    }
    .onAppear { if motionReduced { revealed = true } }
    // Recreate the subtree when motion policy changes so an in-flight
    // transition cannot continue after the user asks for less motion.
    .id(motionReduced)
    .transaction { if motionReduced { $0.animation = nil; $0.disablesAnimations = true } }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Welcome to ARGUS")
  }
}

/// The halo echoes the summon animation so the first thing a user sees is the
/// same visual language the app uses when it is called.
struct IntroHaloView: View {
  let accent: Color
  let phase: CGFloat
  let motionReduced: Bool

  var body: some View {
    ZStack {
      Circle()
        .strokeBorder(
          AngularGradient(colors: IntroPalette.sweep(accent: accent),
            center: .center, angle: .degrees(Double(phase) * 360 - 90)),
          lineWidth: 10)
        .blur(radius: 5)
        .opacity(0.85)
      Circle()
        .strokeBorder(
          AngularGradient(colors: IntroPalette.sweep(accent: accent),
            center: .center, angle: .degrees(Double(phase) * 360 - 90)),
          lineWidth: 4)
      Circle()
        .fill(RadialGradient(
          colors: [accent.opacity(0.26), .clear],
          center: .center, startRadius: 2, endRadius: 64))
      Image(systemName: "eye")
        .font(.system(size: 34, weight: .light))
        .foregroundStyle(.primary)
        .opacity(motionReduced ? 1 : 0.55 + 0.45 * phase)
    }
    .accessibilityHidden(true)
  }
}

private struct IntroPointRow: View {
  let point: IntroPoint
  let accent: Color

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: point.symbol)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(accent)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(point.title).font(.callout.weight(.semibold))
        Text(point.detail).font(.callout).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

struct IntroPoint: Equatable, Sendable {
  let symbol: String
  let title: String
  let detail: String
}

enum IntroMotion {
  static let haloDuration: TimeInterval = 1.4
}

enum IntroPalette {
  /// Mirrors the activation sweep so the intro and the summon read as one idea.
  static func sweep(accent: Color) -> [Color] {
    let base = NSColor(accent)
    return ActivationPalette.sweepColors(from: base).map(Color.init(nsColor:))
  }

  static func titleGradient(accent: Color) -> LinearGradient {
    LinearGradient(colors: sweep(accent: accent), startPoint: .leading, endPoint: .trailing)
  }
}

/// Claims shown on first run.
///
/// These must describe what the prototype actually does. Promising delivery or
/// conversation here would be the first thing a user discovers to be untrue.
enum IntroCopy {
  static let tagline = "A calm, local-first assistant\nfor reminders and reusable prompts."

  static let points = [
    IntroPoint(symbol: "bell.badge", title: "Reminders that stay yours",
      detail: "Stored locally in SQLite with quiet hours and snooze."),
    IntroPoint(symbol: "waveform", title: "Summon by clap or name",
      detail: "Opt-in, on-device listening you start yourself."),
    IntroPoint(symbol: "lock.shield", title: "Explicit permissions",
      detail: "No microphone or speech access until you grant it."),
  ]

  static let honesty =
    "This is a development prototype, not an App Store release. ARGUS has no conversational model and no cloud backend."
}
