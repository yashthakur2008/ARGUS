import SwiftUI
import Testing
@testable import ArgusPresentation

struct VoiceStatusOrbTests {
  @Test func honestStatesHaveDistinctAccessibleLabels() {
    #expect(VoiceStatusOrb.State.off.label == "Voice off")
    #expect(VoiceStatusOrb.State.listening.label == "Listening")
    #expect(VoiceStatusOrb.State.speaking.label == "Speaking")
  }
  @Test @MainActor func publicViewAcceptsEveryStateAndMotionOverride() {
    for state: VoiceStatusOrb.State in [.off, .listening, .speaking] {
      _ = VoiceStatusOrb(state: state, accent: .green, reduceMotion: true).body
    }
  }
}
