import Foundation

public enum ActivationMode: String, CaseIterable, Sendable { case clap, wakeWord, both }
public enum ActivationTrigger: Sendable, Equatable { case clap, wakeWord }

/// A heuristic, not a classifier: require quiet, a sharp RMS/peak rise, and a
/// return to quiet within 100 ms. State is constant-size and audio is never held.
public struct ClapDetector: Sendable {
  private var armed = false
  private var impulseStart: TimeInterval?
  private var lastFrame: TimeInterval?
  private var lastTrigger: TimeInterval?
  public init() {}

  public mutating func process(rms: Double, peak: Double, at time: TimeInterval) -> Bool {
    guard rms.isFinite, peak.isFinite, time.isFinite,
      rms >= 0, peak >= rms, peak <= 1 else {
      armed = false
      impulseStart = nil
      return false
    }
    if let lastFrame, time <= lastFrame || time - lastFrame > 0.15 {
      armed = false
      impulseStart = nil
    }
    lastFrame = time
    let quiet = rms < 0.06 && peak < 0.2
    if let start = impulseStart {
      if time - start > 0.1 {
        impulseStart = nil
        armed = quiet
        return false
      }
      if quiet {
        impulseStart = nil
        armed = true
        guard lastTrigger.map({ time - $0 >= 1.2 }) ?? true else { return false }
        lastTrigger = time
        return true
      }
      return false
    }
    if quiet { armed = true; return false }
    if armed, rms >= 0.12, peak >= 0.65, peak / max(rms, 0.001) >= 2 {
      impulseStart = time
    }
    armed = false
    return false
  }

  public mutating func reset() { self = Self() }
}

/// Matches the whole alphanumeric token "argus". Only a boolean and timestamp
/// survive each call, never a transcript. One activation per recognition utterance.
public struct WakeWordDetector: Sendable {
  private var detectedInUtterance = false
  private var lastTrigger: TimeInterval?
  public init() {}

  public mutating func process(_ text: String, at time: TimeInterval, isFinal: Bool = false) -> Bool {
    defer { if isFinal { detectedInUtterance = false } }
    guard time.isFinite, !detectedInUtterance else { return false }
    let matches = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .contains { $0.lowercased() == "argus" }
    guard matches else { return false }
    detectedInUtterance = true
    guard lastTrigger.map({ time - $0 >= 1.2 }) ?? true else { return false }
    lastTrigger = time
    return true
  }

  public mutating func reset() { self = Self() }
}
