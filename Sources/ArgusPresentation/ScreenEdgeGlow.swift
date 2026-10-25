import AppKit
import QuartzCore

/// Brief, passive feedback only. This controller never activates the app or requests permissions.
/// A single finite pulse settles to a static gradient. Motion changes cancel the pulse immediately.
@MainActor
public final class ScreenEdgeGlowController {
  private let resources = ScreenEdgeGlowResources()
  private let policy = ScreenEdgeGlowPolicy()

  public init() {
    let resources = resources
    resources.motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil, queue: .main
    ) { [weak resources] _ in
      MainActor.assumeIsolated { resources?.refreshMotion() }
    }
    resources.screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak resources] _ in
      Task { @MainActor [weak resources] in resources?.hide() }
    }
  }

  public func show(color: NSColor) {
    show(color: color, reduceMotion: resources.reduceMotion)
  }

  /// Updates visible overlays without restarting their pulse or extending their lifetime.
  public func setReduceMotion(_ value: Bool) {
    resources.reduceMotion = value
    resources.refreshMotion()
  }

  public func show(color: NSColor, reduceMotion: Bool) {
    resources.reduceMotion = reduceMotion
    // Replacing, rather than accumulating, panels also updates the color on repeated triggers.
    resources.hide()
    let epoch = resources.lifetime.begin()
    for screen in NSScreen.screens {
      let frame = screen.frame
      guard !ScreenEdgeGlowGeometry.edges(for: frame.size).isEmpty else { continue }
      let panel = ScreenEdgeGlowPanel(contentRect: frame, policy: policy)
      panel.contentView = ScreenEdgeGlowView(frame: CGRect(origin: .zero, size: frame.size), color: color)
      resources.panels.append(panel)
      // Unlike makeKeyAndOrderFront, this never asks to activate or become key.
      panel.orderFrontRegardless()
      (panel.contentView as? ScreenEdgeGlowView)?.applyMotion(
        systemReduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        overrideReduced: resources.reduceMotion, startPulse: true)
    }
    let resources = resources
    let duration = policy.duration
    resources.hideTask = Task { @MainActor [weak resources] in
      do { try await Task.sleep(for: duration) }
      catch { return }
      guard let resources, resources.lifetime.end(ifCurrent: epoch) else { return }
      resources.hide()
    }
  }

  /// Immediately cancels pending expiry and removes every overlay. Safe to call repeatedly.
  public func hide() {
    resources.hide()
  }

  deinit {
    // Swift 6 deinit may run off actor. Transfer the isolated resource owner, not AppKit objects,
    // to the main actor. Neither the observer nor the expiry task retains this controller.
    let resources = resources
    Task { @MainActor in resources.dispose() }
  }
}

/// Owns only native resources, allowing teardown to remain main-actor isolated during deinit.
@MainActor
private final class ScreenEdgeGlowResources {
  var panels: [ScreenEdgeGlowPanel] = []
  var hideTask: Task<Void, Never>?
  var screenObserver: (any NSObjectProtocol)?
  var lifetime = ScreenEdgeGlowLifetime()
  var reduceMotion = false
  var motionObserver: (any NSObjectProtocol)?

  func refreshMotion() {
    for panel in panels {
      (panel.contentView as? ScreenEdgeGlowView)?.applyMotion(
        systemReduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        overrideReduced: reduceMotion, startPulse: false)
    }
  }

  func hide() {
    lifetime.invalidate()
    hideTask?.cancel()
    hideTask = nil
    for panel in panels {
      panel.orderOut(nil)
      panel.close()
    }
    panels.removeAll()
  }

  func dispose() {
    hide()
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    screenObserver = nil
    if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
    motionObserver = nil
  }
}

@MainActor
private final class ScreenEdgeGlowPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init(contentRect: CGRect, policy: ScreenEdgeGlowPolicy) {
    super.init(contentRect: contentRect, styleMask: policy.styleMask, backing: .buffered, defer: true)
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = policy.ignoresMouseEvents
    collectionBehavior = policy.collectionBehavior
    animationBehavior = policy.animationBehavior
    level = .statusBar
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = true
    isMovable = false
    isExcludedFromWindowsMenu = true
    setAccessibilityElement(false)
  }
}

/// Iridescent companions for the user's accent colour.
///
/// A single flat colour cannot read as light travelling around the border,
/// because every edge brightens at once. The sweep needs neighbouring hues to
/// shade between, so offsets stay anchored to the chosen accent and a user's
/// colour remains recognisably theirs.
enum ActivationPalette {
  static let hueOffsets: [CGFloat] = [0, 40, 95, 170, 260, 310]

  static func sweepColors(from accent: NSColor) -> [NSColor] {
    guard let base = accent.usingColorSpace(.sRGB) else { return [accent, accent] }
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    // A greyscale accent has no hue to rotate, so borrow a floor of saturation
    // rather than letting the sweep collapse into one flat tone.
    let spread = max(saturation, 0.45)
    var colors = hueOffsets.map { offset -> NSColor in
      let shifted = (hue + offset / 360).truncatingRemainder(dividingBy: 1)
      return NSColor(hue: shifted, saturation: spread,
        brightness: min(1, brightness + 0.12), alpha: alpha)
    }
    // A conic gradient wraps, so the final stop must equal the first or a hard
    // seam appears at the top of the screen as it rotates.
    if let first = colors.first { colors.append(first) }
    return colors
  }

  static func evenLocations(count: Int) -> [NSNumber] {
    guard count > 1 else { return [0] }
    return (0..<count).map { NSNumber(value: Double($0) / Double(count - 1)) }
  }
}

@MainActor
final class ScreenEdgeGlowView: NSView {
  private let gradient = CAGradientLayer()
  private let ring = CAShapeLayer()
  /// Holds the border-shaped mask still while the gradient turns inside it.
  private let aperture = CALayer()
  /// Draws the halo, because a mask layer never renders its own shadow.
  private let halo = CAShapeLayer()

  init(frame: CGRect, color: NSColor) {
    super.init(frame: frame)
    setAccessibilityElement(false)
    wantsLayer = true
    guard let layer, !ScreenEdgeGlowGeometry.edges(for: frame.size).isEmpty else { return }
    layer.opacity = 0.82

    let width = min(5, bounds.width / 2, bounds.height / 2)
    let border = CGPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
      cornerWidth: 12, cornerHeight: 12, transform: nil)

    halo.frame = bounds
    halo.path = border
    halo.fillColor = nil
    halo.strokeColor = color.cgColor
    halo.lineWidth = width
    halo.shadowColor = color.cgColor
    halo.shadowOpacity = 0.85
    halo.shadowRadius = 10
    halo.shadowOffset = .zero
    layer.addSublayer(halo)

    // The mask belongs to this container rather than to the gradient: a mask
    // is a sublayer, so rotating the gradient would rotate its own mask and
    // smear the border diagonally across the screen instead of around it.
    aperture.frame = bounds
    ring.frame = bounds
    ring.path = border
    ring.fillColor = nil
    ring.strokeColor = NSColor.white.cgColor
    ring.lineWidth = width
    aperture.mask = ring

    // A conic gradient puts every hue at a different angle, so turning it reads
    // as light travelling around the border. It is squared to the diagonal so
    // rotation never exposes an uncovered corner.
    let reach = (bounds.width * bounds.width + bounds.height * bounds.height).squareRoot()
    gradient.type = .conic
    gradient.frame = CGRect(x: bounds.midX - reach / 2, y: bounds.midY - reach / 2,
      width: reach, height: reach)
    gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
    gradient.endPoint = CGPoint(x: 0.5, y: 0)
    let sweep = ActivationPalette.sweepColors(from: color)
    gradient.colors = sweep.map(\.cgColor)
    gradient.locations = ActivationPalette.evenLocations(count: sweep.count)
    aperture.addSublayer(gradient)
    layer.addSublayer(aperture)
  }

  /// Preference updates only cancel. Disabling Reduce Motion never replays old feedback.
  func applyMotion(systemReduced: Bool, overrideReduced: Bool, startPulse: Bool) {
    guard let layer else { return }
    if systemReduced || overrideReduced {
      for target in [layer, aperture, gradient, ring, halo] { target.removeAllAnimations() }
      return
    }
    guard startPulse, !ScreenEdgeGlowGeometry.edges(for: bounds.size).isEmpty else { return }

    // Arriving: a fast bloom that overshoots before settling, so the summon has
    // an impact rather than fading up linearly.
    let bloom = CAKeyframeAnimation(keyPath: "opacity")
    bloom.values = [0, 1, 0.68, 0.92, 0.82]
    bloom.keyTimes = [0, 0.18, 0.45, 0.72, 1]
    bloom.duration = ScreenEdgeGlowMotion.duration
    bloom.repeatCount = 0
    bloom.isRemovedOnCompletion = true
    bloom.timingFunctions = Array(
      repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
    layer.add(bloom, forKey: ScreenEdgeGlowMotion.pulseKey)

    // One full rotation carries the hues once around every edge. A partial turn
    // would leave the colours parked somewhere different from where they began.
    let travel = CABasicAnimation(keyPath: "transform.rotation.z")
    travel.fromValue = 0
    travel.toValue = 2 * Double.pi
    travel.duration = ScreenEdgeGlowMotion.duration
    travel.repeatCount = 0
    travel.isRemovedOnCompletion = true
    travel.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    gradient.add(travel, forKey: ScreenEdgeGlowMotion.sweepKey)

    // The halo widens as the sweep passes, which keeps the border from looking
    // like a flat painted rectangle.
    let breathe = CAKeyframeAnimation(keyPath: "shadowRadius")
    breathe.values = [4, 22, 11]
    breathe.keyTimes = [0, 0.3, 1]
    breathe.duration = ScreenEdgeGlowMotion.duration
    breathe.repeatCount = 0
    breathe.isRemovedOnCompletion = true
    breathe.timingFunctions = Array(
      repeating: CAMediaTimingFunction(name: .easeOut), count: 2)
    halo.add(breathe, forKey: ScreenEdgeGlowMotion.breatheKey)
  }

  required init?(coder: NSCoder) { nil }
  override var isOpaque: Bool { false }
}

/// Timings shared by the summon animation and the checks that bound it.
enum ScreenEdgeGlowMotion {
  /// Must stay inside the panel lifetime, or motion would be cut off mid-sweep.
  static let duration: CFTimeInterval = 1.1
  static let pulseKey = "activationPulse"
  static let sweepKey = "activationSweep"
  static let breatheKey = "activationBreathe"
  static let keys = [pulseKey, sweepKey, breatheKey]
}

struct ScreenEdgeGlowPolicy {
  let duration: Duration = .milliseconds(1_200)
  let animationBehavior: NSWindow.AnimationBehavior = .none
  let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
  let ignoresMouseEvents = true
  let collectionBehavior: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
  ]
}

enum ScreenEdgeGlowGeometry {
  /// Panel content uses local coordinates even for screens left of/below the primary screen.
  static func edges(for size: CGSize) -> [CGRect] {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return [] }
    let width = min(6, size.width / 2, size.height / 2)
    return [
      CGRect(x: 0, y: 0, width: size.width, height: width),
      CGRect(x: 0, y: size.height - width, width: size.width, height: width),
      CGRect(x: 0, y: width, width: width, height: size.height - 2 * width),
      CGRect(x: size.width - width, y: width, width: width, height: size.height - 2 * width),
    ].filter { $0.width > 0 && $0.height > 0 }
  }
}

/// Cancellation alone is insufficient if an old expiry has already been enqueued.
struct ScreenEdgeGlowLifetime {
  private var epoch: UInt64 = 0
  private var isVisible = false

  mutating func begin() -> UInt64 {
    epoch &+= 1
    isVisible = true
    return epoch
  }

  mutating func invalidate() {
    epoch &+= 1
    isVisible = false
  }

  mutating func end(ifCurrent candidate: UInt64) -> Bool {
    guard isVisible, candidate == epoch else { return false }
    invalidate()
    return true
  }
}
