import Foundation
import AVFoundation
import Speech
import ArgusCore

struct OnDeviceSpeechPolicy {
  static func supports(locale: Locale, supportedLocales: Set<Locale>) -> Bool {
    supportedLocales.contains {
      $0.language.languageCode == locale.language.languageCode && $0.region == locale.region
    }
  }

  static func permitsRecognition(languageSupported: Bool, available: Bool, supportsOnDevice: Bool) -> Bool {
    languageSupported && available && supportsOnDevice
  }
}

@MainActor final class NativeAudioActivationBackend: AudioActivationBackend {
  func existingPermissionsAllow(mode: ActivationMode) -> Bool {
    NativeActivationPermissionChecker().isAuthorized(for: mode)
  }
  func requestMicrophonePermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
    default: return false
    }
  }
  func requestSpeechPermission() async -> Bool {
    if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
    guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return false }
    return await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
    }
  }
  func makeSession() -> any AudioActivationSession { NativeAudioActivationSession() }
}

@MainActor protocol ActivationAudioDriver: AnyObject {
  func start(onLevels: @escaping @MainActor @Sendable (Double, Double, Double) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void) throws
  func stop()
}
@MainActor protocol ActivationSpeechDriver: AnyObject {
  func start(onResult: @escaping @MainActor @Sendable (String, Double, Bool) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void) throws
  func stop()
}
@MainActor protocol ActivationTimer: AnyObject { func cancel() }
@MainActor protocol ActivationScheduler: AnyObject {
  func schedule(after seconds: Double, action: @escaping @MainActor @Sendable () -> Void) -> any ActivationTimer
}
