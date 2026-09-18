import ArgusPlatform

extension ElevenLabsSpeechFailure {
  /// Deliberately formats only typed cases, never provider bodies or underlying errors.
  var presentationMessage: String {
    switch self {
    case .disclosureRequired:
      "ElevenLabs needs your text-transmission consent in Settings before speaking."
    case .credentialRequired:
      "ElevenLabs voice needs an available API key in the login Keychain. Review Settings."
    case .httpStatus(401), .httpStatus(403):
      "ElevenLabs denied voice access. Check the API key and account permissions."
    case .httpStatus(429):
      "ElevenLabs usage limit reached. Review your account. No subscription was purchased."
    case .httpStatus:
      "ElevenLabs could not provide speech. Try again later."
    case .network, .timedOut:
      "ElevenLabs could not be reached in time. Check your connection and try again."
    case .redirectRejected:
      "ElevenLabs redirected the request. ARGUS blocked it to protect your text and API key."
    case .invalidResponse, .invalidAudio, .responseTooLarge, .playback:
      "ElevenLabs audio could not be played safely. No system voice was used."
    case .emptyText, .invalidRequest:
      "ElevenLabs speech request was invalid. No system voice was used."
    }
  }
}
