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

@MainActor
final class ScreenEdgeGlowView: NSView {
  init(frame: CGRect, color: NSColor) {
    super.init(frame: frame)
    setAccessibilityElement(false)
    wantsLayer = true
    guard let layer, !ScreenEdgeGlowGeometry.edges(for: frame.size).isEmpty else { return }
    layer.opacity = 0.82

    let gradient = CAGradientLayer()
    gradient.frame = bounds
    gradient.startPoint = CGPoint(x: 0, y: 0)
    gradient.endPoint = CGPoint(x: 1, y: 1)
    gradient.colors = [
      color.blended(withFraction: 0.35, of: .white) ?? color,
      color,
      color.blended(withFraction: 0.30, of: .black) ?? color,
      color.blended(withFraction: 0.18, of: .white) ?? color,
    ].map { $0.cgColor }
    gradient.locations = [0, 0.35, 0.7, 1]

    let width = min(5, bounds.width / 2, bounds.height / 2)
    let ring = CAShapeLayer()
    ring.frame = bounds
    ring.path = CGPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
      cornerWidth: 12, cornerHeight: 12, transform: nil)
    ring.fillColor = nil
    ring.strokeColor = NSColor.white.cgColor
    ring.lineWidth = width
    ring.shadowColor = NSColor.white.cgColor
    ring.shadowOpacity = 0.85
    ring.shadowRadius = 10
    ring.shadowOffset = .zero
    gradient.mask = ring
    layer.addSublayer(gradient)
  }

  /// Preference updates only cancel. Disabling Reduce Motion never replays old feedback.
  func applyMotion(systemReduced: Bool, overrideReduced: Bool, startPulse: Bool) {
    guard let layer else { return }
    if systemReduced || overrideReduced {
      layer.removeAllAnimations()
      return
    }
    guard startPulse, !ScreenEdgeGlowGeometry.edges(for: bounds.size).isEmpty else { return }
    let pulse = CAKeyframeAnimation(keyPath: "opacity")
    pulse.values = [0.55, 1, 0.82]
    pulse.keyTimes = [0, 0.4, 1]
    pulse.duration = 0.9
    pulse.repeatCount = 0
    pulse.isRemovedOnCompletion = true
    pulse.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
    layer.add(pulse, forKey: "activationPulse")
  }

  required init?(coder: NSCoder) { nil }
  override var isOpaque: Bool { false }
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
