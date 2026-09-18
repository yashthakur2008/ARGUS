import Foundation
import ServiceManagement

public enum LoginItemStatus: Equatable, Sendable {
  case disabled, enabled, requiresApproval, unavailable
}

@MainActor
public protocol LoginItemService: AnyObject {
  var status: LoginItemStatus { get }
  func setEnabled(_ enabled: Bool) throws
}

/// Native main-app registration only, with no after-Quit helper.
/// Construction is read-only and never registers a login item.
@MainActor
public final class NativeLoginItemService: LoginItemService {
  private let isAppBundle: Bool

  public init() {
    isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
      && Bundle.main.bundleIdentifier != nil
  }

  public var status: LoginItemStatus {
    guard isAppBundle else { return .unavailable }
    return Self.mapStatus(SMAppService.mainApp.status)
  }

  public func setEnabled(_ enabled: Bool) throws {
    guard isAppBundle else { throw LoginItemError.unavailable }
    // The controller also refreshes after success AND failure. Read OS state, never defaults.
    defer { _ = status }
    if enabled { try SMAppService.mainApp.register() }
    else { try SMAppService.mainApp.unregister() }
  }

  static func mapStatus(_ status: SMAppService.Status) -> LoginItemStatus {
    switch status {
    case .notRegistered: .disabled
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notFound: .unavailable
    @unknown default: .unavailable
    }
  }
}

private enum LoginItemError: LocalizedError {
  case unavailable
  var errorDescription: String? {
    "Launch at login requires an installed macOS app bundle."
  }
}
