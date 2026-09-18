import ArgusPlatform
import Foundation
import Observation

/// Displays OS truth. Initialization and refresh never change login registration.
@MainActor @Observable
public final class LoginItemController {
  public private(set) var status: LoginItemStatus
  public var isEnabled: Bool { status == .enabled }
  public private(set) var isWorking = false
  public private(set) var errorMessage: String?
  private let service: any LoginItemService

  public var statusText: String {
    switch status {
    case .disabled: "Launch at login is off."
    case .enabled: "Launch at login is enabled."
    case .requiresApproval: "Launch at login requires approval in System Settings › General › Login Items."
    case .unavailable: "Launch at login is unavailable. macOS cannot recognize the login service in this build or installation."
    }
  }

  public init(service: any LoginItemService) {
    self.service = service
    status = service.status
  }

  /// Only explicit user actions call this method. Never persists an optimistic enabled flag.
  public func setEnabled(_ enabled: Bool) {
    guard !isWorking else { return }
    isWorking = true
    defer { refresh(); isWorking = false }
    do {
      try service.setEnabled(enabled)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func refresh() { status = service.status }
}
