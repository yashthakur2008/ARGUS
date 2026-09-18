import Foundation
import ArgusCore

/// Only explicit setters write preferences. Constructing a controller does not opt in.
@MainActor struct VoicePreferences {
  let defaults: UserDefaults
  var alwaysListen: Bool {
    get { defaults.bool(forKey: "voice.alwaysListen") }
    nonmutating set { defaults.set(newValue, forKey: "voice.alwaysListen") }
  }
  var spokenResponses: Bool {
    get { defaults.bool(forKey: "voice.spokenResponses") }
    nonmutating set { defaults.set(newValue, forKey: "voice.spokenResponses") }
  }
  var preferredMode: ActivationMode? {
    get {
      switch defaults.string(forKey: "voice.activationMode") {
      case "clap": .clap
      case "wakeWord": .wakeWord
      case "both": .both
      default: nil
      }
    }
    nonmutating set {
      let value: String?
      switch newValue {
      case .clap: value = "clap"
      case .wakeWord: value = "wakeWord"
      case .both: value = "both"
      case nil: value = nil
      }
      defaults.set(value, forKey: "voice.activationMode")
    }
  }
}
