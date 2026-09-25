import Testing
@testable import ArgusPresentation

struct PermissionSupportTests {
  @Test func defaultChecklistExplainsRequiredPermissionActions() {
    let checklist = PermissionSupportChecklist.defaultItems

    #expect(checklist.map(\.id) == [
      "notifications", "microphone", "speech", "accessibility", "elevenlabs", "launchAtLogin"
    ])
    #expect(checklist.first { $0.id == "microphone" }?.requestActionTitle == "Request microphone access")
    #expect(checklist.first { $0.id == "speech" }?.requestActionTitle == "Request speech recognition")
    #expect(checklist.first { $0.id == "accessibility" }?.requestActionTitle == "Request Accessibility listing")
    #expect(checklist.first { $0.id == "accessibility" }?.systemSettingsTitle == "Open Accessibility settings")
    #expect(checklist.first { $0.id == "elevenlabs" }?.systemSettingsTitle == nil)
    #expect(checklist.first { $0.id == "launchAtLogin" }?.systemSettingsTitle == nil)
  }

  @Test func missingBundledChangelogMakesUpdateInfoActionable() {
    let info = AppUpdateInfo(version: "0.1.8", build: "9", commit: "abc1234", latestEntry: nil)

    #expect(info.freshnessLine == "This build is missing its bundled changelog. Rebuild or reinstall ARGUS from the latest app bundle.")
    #expect(info.recoveryLine == "The running app may be older than the source checkout if Settings does not show What's new.")
  }
}
