import ApplicationServices
import AVFoundation
import Foundation
import Speech

@MainActor public protocol SystemPermissionRequesting {
  func requestMicrophone() async -> Bool
  func requestSpeechRecognition() async -> Bool
  func requestAccessibilityListing() -> Bool
}

@MainActor public struct NativeSystemPermissionRequester: SystemPermissionRequesting {
  public init() {}

  public func requestMicrophone() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
    default: return false
    }
  }

  public func requestSpeechRecognition() async -> Bool {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: return true
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
      }
    default: return false
    }
  }

  public func requestAccessibilityListing() -> Bool {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }
}
