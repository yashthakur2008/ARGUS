import ArgusCore
import AVFoundation
import Speech

/// A status query only. Neither implementation nor callers request authorization here.
@MainActor public protocol ActivationPermissionChecking {
  func isAuthorized(for mode: ActivationMode) -> Bool
}

@MainActor public struct NativeActivationPermissionChecker: ActivationPermissionChecking {
  public init() {}
  public func isAuthorized(for mode: ActivationMode) -> Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
      && (mode == .clap || SFSpeechRecognizer.authorizationStatus() == .authorized)
  }
}
