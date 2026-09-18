import Foundation
import Testing
import ArgusPlatform
@testable import ArgusPresentation

@MainActor
private final class FakeLoginItemService: LoginItemService {
  var currentStatus: LoginItemStatus = .disabled
  var reads = 0
  var changes: [Bool] = []
  var failure: Error?
  var resultStatus: LoginItemStatus?
  var status: LoginItemStatus { reads += 1; return currentStatus }
  func setEnabled(_ enabled: Bool) throws {
    changes.append(enabled)
    currentStatus = resultStatus ?? (enabled ? .enabled : .disabled)
    if let failure { throw failure }
  }
}
private struct LoginFailure: LocalizedError {
  var errorDescription: String? { "Registration was denied." }
}

@Suite @MainActor
struct LoginItemControllerTests {
  @Test func initializationOnlyReadsActualStatus() {
    let service = FakeLoginItemService()
    service.currentStatus = .enabled
    let controller = LoginItemController(service: service)
    #expect(service.reads == 1)
    #expect(service.changes.isEmpty)
    #expect(controller.isEnabled)
    #expect(!controller.isWorking)
  }
  @Test func defaultDisabledDoesNotRegister() {
    let service = FakeLoginItemService()
    let controller = LoginItemController(service: service)
    #expect(controller.status == .disabled)
    #expect(!controller.isEnabled)
    #expect(controller.errorMessage == nil)
    #expect(service.changes.isEmpty)
  }
  @Test func userEnableAndDisableMutateExactlyOnceEach() {
    let service = FakeLoginItemService()
    let controller = LoginItemController(service: service)
    controller.setEnabled(true)
    #expect(service.changes == [true])
    #expect(controller.isEnabled)
    controller.setEnabled(false)
    #expect(service.changes == [true, false])
    #expect(!controller.isEnabled)
    #expect(!controller.isWorking)
  }
  @Test func approvalIsNotEnabledAndRemainsActionable() {
    let service = FakeLoginItemService()
    service.resultStatus = .requiresApproval
    let controller = LoginItemController(service: service)
    controller.setEnabled(true)
    #expect(controller.status == .requiresApproval)
    #expect(!controller.isEnabled)
    #expect(controller.statusText.contains("approval"))
    controller.setEnabled(false)
    #expect(service.changes == [true, false])
  }
  @Test func failurePreservesMessageAndRefreshesActualState() {
    let service = FakeLoginItemService()
    service.failure = LoginFailure()
    service.resultStatus = .requiresApproval
    let controller = LoginItemController(service: service)
    controller.setEnabled(true)
    #expect(controller.errorMessage == "Registration was denied.")
    #expect(controller.status == .requiresApproval)
    #expect(!controller.isEnabled)
    #expect(!controller.isWorking)
    controller.refresh()
    #expect(controller.errorMessage == "Registration was denied.")
    service.failure = nil
    controller.setEnabled(false)
    #expect(controller.errorMessage == nil)
  }
  @Test func repeatedRefreshNeverMutatesAndObservesExternalChanges() {
    let service = FakeLoginItemService()
    let controller = LoginItemController(service: service)
    for status in [LoginItemStatus.enabled, .requiresApproval, .unavailable, .disabled] {
      service.currentStatus = status
      controller.refresh()
      #expect(controller.status == status)
      #expect(controller.isEnabled == (status == .enabled))
      #expect(!controller.statusText.isEmpty)
    }
    #expect(service.changes.isEmpty)
    #expect(service.reads == 5)
  }
}
