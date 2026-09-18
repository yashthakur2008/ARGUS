import Testing
import ServiceManagement
@testable import ArgusPlatform

@Suite @MainActor
struct LoginItemServiceTests {
  // Pure mapping only. Never instantiate SMAppService or call register/unregister in tests.
  @Test func nativeStatusesRemainDistinct() {
    #expect(NativeLoginItemService.mapStatus(.notRegistered) == .disabled)
    #expect(NativeLoginItemService.mapStatus(.enabled) == .enabled)
    #expect(NativeLoginItemService.mapStatus(.requiresApproval) == .requiresApproval)
    #expect(NativeLoginItemService.mapStatus(.notFound) == .unavailable)
  }
}
