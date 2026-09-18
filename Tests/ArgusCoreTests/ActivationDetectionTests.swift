import Testing
@testable import ArgusCore

@Test func clapRequiresShortImpulseThenQuiet() {
  var detector = ClapDetector()
  #expect(!detector.process(rms: 0.01, peak: 0.02, at: 0) == true)
  #expect(!detector.process(rms: 0.3, peak: 0.95, at: 0.02) == true)
  #expect(detector.process(rms: 0.01, peak: 0.02, at: 0.04) == true)
}
@Test func sustainedLoudnessIsNotClap() {
  var detector = ClapDetector()
  for index in 0..<100 {
    #expect(!detector.process(rms: 0.4, peak: 0.95, at: Double(index) * 0.02) == true)
  }
  #expect(!detector.process(rms: 0.01, peak: 0.02, at: 2.0) == true)
}
@Test func clapCooldownAndReset() {
  var detector = ClapDetector()
  func impulse(_ t: Double) -> Bool {
    _ = detector.process(rms: 0.01, peak: 0.02, at: t)
    _ = detector.process(rms: 0.3, peak: 0.95, at: t + 0.02)
    return detector.process(rms: 0.01, peak: 0.02, at: t + 0.04)
  }
  #expect(impulse(0))
  #expect(!impulse(0.2))
  #expect(impulse(2))
  detector.reset()
  #expect(impulse(2.2))
}
@Test func wakeMatchesExactTokenAndDeduplicatesPartials() {
  var detector = WakeWordDetector()
  #expect(!detector.process("superargus arguslike", at: 0) == true)
  #expect(detector.process("Hey, ARGUS!", at: 1) == true)
  #expect(!detector.process("Hey, ARGUS! please", at: 4) == true)
  #expect(!detector.process("Hey, ARGUS! please", at: 5, isFinal: true) == true)
  #expect(detector.process("argus", at: 6) == true)
}
@Test func wakeCooldownAndReset() {
  var detector = WakeWordDetector()
  #expect(detector.process("argus", at: 0, isFinal: true) == true)
  #expect(!detector.process("argus", at: 0.2, isFinal: true) == true)
  #expect(detector.process("argus", at: 2, isFinal: true) == true)
  detector.reset()
  #expect(detector.process("argus", at: 2.1) == true)
}
