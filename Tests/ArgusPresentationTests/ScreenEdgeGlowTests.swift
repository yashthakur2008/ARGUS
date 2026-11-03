import AppKit
import Testing
@testable import ArgusPresentation

struct ScreenEdgeGlowTests {
  @Test func borderUsesLocalCoordinatesForOffsetDisplay() {
    let frame = CGRect(x: -1920, y: 300, width: 1920, height: 1080)
    let edges = ScreenEdgeGlowGeometry.edges(for: frame.size)
    #expect(edges.count == 4)
    #expect(edges.contains(CGRect(x: 0, y: 0, width: 1920, height: 6)))
    #expect(edges.contains(CGRect(x: 0, y: 1074, width: 1920, height: 6)))
    #expect(edges.contains(CGRect(x: 0, y: 6, width: 6, height: 1068)))
    #expect(edges.contains(CGRect(x: 1914, y: 6, width: 6, height: 1068)))
  }

  @Test func tinyAndInvalidDisplaysStayBounded() {
    for size in [CGSize(width: 1, height: 1), CGSize(width: 8, height: 4)] {
      let bounds = CGRect(origin: .zero, size: size)
      let edges = ScreenEdgeGlowGeometry.edges(for: size)
      #expect(!edges.isEmpty)
      #expect(edges.allSatisfy { bounds.contains($0) && $0.width > 0 && $0.height > 0 })
    }
    for size in [CGSize.zero, CGSize(width: -1, height: 100), CGSize(width: CGFloat.infinity, height: 100)] {
      #expect(ScreenEdgeGlowGeometry.edges(for: size).isEmpty)
    }
  }

  @Test func feedbackPreservesBriefPassiveWindowPolicy() {
    let policy = ScreenEdgeGlowPolicy()
    #expect(policy.duration > .zero)
    #expect(policy.duration <= .seconds(2))
    #expect(policy.animationBehavior == .none)
    #expect(policy.styleMask == [.borderless, .nonactivatingPanel])
    #expect(policy.styleMask.contains(.nonactivatingPanel))
    #expect(policy.ignoresMouseEvents)
    #expect(policy.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(policy.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(policy.collectionBehavior.contains(.ignoresCycle))
  }

  @Test func staleHideCannotEndNewPresentation() {
    var lifetime = ScreenEdgeGlowLifetime()
    let first = lifetime.begin()
    let second = lifetime.begin()
    #expect(first != second)
    let staleEnded = lifetime.end(ifCurrent: first)
    let currentEnded = lifetime.end(ifCurrent: second)
    let endedTwice = lifetime.end(ifCurrent: second)
    #expect(!staleEnded)
    #expect(currentEnded)
    #expect(!endedTwice)
  }

  @Test func explicitHideAndScreenCleanupInvalidatePendingHide() {
    var lifetime = ScreenEdgeGlowLifetime()
    let first = lifetime.begin()
    lifetime.invalidate()
    let staleEnded = lifetime.end(ifCurrent: first)
    #expect(!staleEnded)
    let next = lifetime.begin()
    let nextEnded = lifetime.end(ifCurrent: next)
    #expect(nextEnded)
  }
}

@MainActor struct ScreenEdgeGlowAnimationTests {
  private func sweepView() -> ScreenEdgeGlowView {
    ScreenEdgeGlowView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), color: .systemGreen)
  }

  /// Every layer a motion preference must be able to reach, at any depth.
  private func allLayers(_ view: ScreenEdgeGlowView) -> [CALayer] {
    func walk(_ layer: CALayer) -> [CALayer] {
      [layer] + (layer.mask.map(walk) ?? []) + (layer.sublayers ?? []).flatMap(walk)
    }
    return view.layer.map(walk) ?? []
  }

  private func activeKeys(_ view: ScreenEdgeGlowView) -> [String] {
    allLayers(view).flatMap { $0.animationKeys() ?? [] }
  }

  @Test func pulseIsFiniteAndRemovedByEitherMotionPreference() {
    let view = sweepView()
    view.applyMotion(systemReduced: false, overrideReduced: false, startPulse: true)
    let pulse = view.layer?.animation(forKey: ScreenEdgeGlowMotion.pulseKey)
    #expect(pulse != nil)
    #expect(pulse?.duration == ScreenEdgeGlowMotion.duration)
    #expect(pulse?.repeatCount == 0)
    #expect(pulse?.isRemovedOnCompletion == true)
    view.applyMotion(systemReduced: true, overrideReduced: false, startPulse: false)
    #expect(activeKeys(view).isEmpty)
    view.applyMotion(systemReduced: false, overrideReduced: false, startPulse: false)
    #expect(activeKeys(view).isEmpty)
    view.applyMotion(systemReduced: false, overrideReduced: false, startPulse: true)
    view.applyMotion(systemReduced: false, overrideReduced: true, startPulse: false)
    #expect(activeKeys(view).isEmpty)
  }

  @Test func reducedMotionNeverStartsPulse() {
    for flags in [(true, false), (false, true), (true, true)] {
      let view = sweepView()
      view.applyMotion(systemReduced: flags.0, overrideReduced: flags.1, startPulse: true)
      #expect(activeKeys(view).isEmpty)
    }
  }

  @Test func summonTravelsAroundTheBorderRatherThanBlinkingOnce() {
    let view = sweepView()
    view.applyMotion(systemReduced: false, overrideReduced: false, startPulse: true)

    // A rotating conic sweep is what makes the summon read as motion around
    // the screen instead of every edge brightening together.
    let keys = Set(activeKeys(view))
    for key in ScreenEdgeGlowMotion.keys { #expect(keys.contains(key)) }
  }

  @Test func everyPartOfTheSummonIsFiniteAndFitsThePanelLifetime() {
    let view = sweepView()
    view.applyMotion(systemReduced: false, overrideReduced: false, startPulse: true)
    let policy = ScreenEdgeGlowPolicy()
    let lifetime = Double(policy.duration.components.seconds)
      + Double(policy.duration.components.attoseconds) / 1e18

    var found = 0
    for candidate in allLayers(view) {
      for key in candidate.animationKeys() ?? [] {
        guard let animation = candidate.animation(forKey: key) else { continue }
        found += 1
        #expect(animation.repeatCount == 0, "\(key) repeats")
        #expect(animation.isRemovedOnCompletion, "\(key) is not removed")
        // Motion outlasting the overlay would be cut off mid-sweep.
        #expect(animation.duration <= lifetime, "\(key) outlives the panel")
      }
    }
    #expect(found == ScreenEdgeGlowMotion.keys.count)
  }

  @Test func theRotatingSweepStaysInsideTheBorder() {
    // A mask is a sublayer, so masking the gradient itself made the border
    // rotate too and smeared colour diagonally across the whole screen.
    // Observed on a real display before the mask moved to a still container.
    let view = sweepView()
    guard let root = view.layer else { Issue.record("Expected a backing layer"); return }

    let rotating = (root.sublayers ?? []).flatMap { $0.sublayers ?? [] }
    let gradient = rotating.compactMap { $0 as? CAGradientLayer }.first
    #expect(gradient != nil, "Expected the gradient to sit inside a container")
    #expect(gradient?.mask == nil, "Rotating the gradient would rotate its own mask")

    // The clip must live on a layer that never rotates.
    let masked = (root.sublayers ?? []).filter { $0.mask != nil }
    #expect(masked.count == 1)
    #expect(masked.first?.frame == view.bounds)
  }

  @Test func theSweepCoversEveryCornerThroughAFullTurn() {
    // A gradient sized to the bounds leaves corners uncovered once rotated,
    // which would blank part of the border mid-sweep.
    let view = sweepView()
    guard let root = view.layer else { Issue.record("Expected a backing layer"); return }
    let gradient = (root.sublayers ?? []).flatMap { $0.sublayers ?? [] }
      .compactMap { $0 as? CAGradientLayer }.first
    guard let gradient else { Issue.record("Expected a gradient"); return }

    let diagonal = (view.bounds.width * view.bounds.width
      + view.bounds.height * view.bounds.height).squareRoot()
    #expect(gradient.frame.width >= diagonal)
    #expect(gradient.frame.height >= diagonal)
    // Centred, or rotation would swing it off the screen.
    #expect(abs(gradient.frame.midX - view.bounds.midX) < 0.5)
    #expect(abs(gradient.frame.midY - view.bounds.midY) < 0.5)
  }

  @Test func theHaloIsDrawnByALayerThatCanActuallyRenderIt() {
    // A layer used as a mask contributes shape only, so a shadow set on it
    // never appears. The halo therefore needs its own visible layer.
    let view = sweepView()
    guard let root = view.layer else { Issue.record("Expected a backing layer"); return }

    let shadowed = (root.sublayers ?? []).filter { $0.shadowOpacity > 0 && $0.mask == nil }
    #expect(shadowed.count == 1)
    #expect(shadowed.first?.shadowRadius ?? 0 > 0)
  }

  @Test func motionCancellationReachesNestedSweepLayers() {
    // The sweep and halo live on sublayers, so cancelling only the root layer
    // would leave them animating after the user asks for reduced motion.
    let view = sweepView()
    view.applyMotion(systemReduced: false, overrideReduced: false, startPulse: true)
    #expect(!activeKeys(view).isEmpty)
    view.applyMotion(systemReduced: true, overrideReduced: false, startPulse: true)
    #expect(activeKeys(view).isEmpty)
  }
}

struct ActivationPaletteTests {
  @Test func sweepStaysAnchoredToTheChosenAccent() {
    let accent = NSColor(srgbRed: 0.4, green: 0.78, blue: 0.57, alpha: 1)
    let colors = ActivationPalette.sweepColors(from: accent)

    #expect(colors.count == 7)
    // The user's colour must still lead the sweep, not be replaced by a preset.
    var accentHue: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    accent.usingColorSpace(.sRGB)?.getHue(&accentHue, saturation: &s, brightness: &b, alpha: &a)
    var firstHue: CGFloat = 0
    colors[0].usingColorSpace(.sRGB)?.getHue(&firstHue, saturation: &s, brightness: &b, alpha: &a)
    #expect(abs(firstHue - accentHue) < 0.01)
  }

  @Test func conicSweepWrapsWithoutASeam() {
    let colors = ActivationPalette.sweepColors(from: .systemTeal)
    // A conic gradient meets itself, so unequal ends would show a hard line.
    #expect(colors.first?.usingColorSpace(.sRGB) == colors.last?.usingColorSpace(.sRGB))
  }

  @Test func greyscaleAccentStillProducesVisibleMotion() {
    // Pure grey still needs shading to show motion without inventing a hue.
    let colors = ActivationPalette.sweepColors(from: .white)
    let distinct = Set(colors.map { $0.usingColorSpace(.sRGB)?.description ?? "" })
    #expect(distinct.count > 1)
  }

  @Test func gradientStopsSpanTheWholeSweep() {
    let locations = ActivationPalette.evenLocations(count: 7)
    #expect(locations.first?.doubleValue == 0)
    #expect(locations.last?.doubleValue == 1)
    #expect(locations.count == 7)
    #expect(zip(locations, locations.dropFirst()).allSatisfy { $0.doubleValue < $1.doubleValue })
    #expect(ActivationPalette.evenLocations(count: 1).count == 1)
  }
}
