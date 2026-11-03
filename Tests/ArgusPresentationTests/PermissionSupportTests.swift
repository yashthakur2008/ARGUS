import Foundation
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

  @Test func everyRowOfferingSettingsOpensItsOwnPrivacyPane() {
    for item in PermissionSupportChecklist.defaultItems where item.systemSettingsTitle != nil {
      let string = PermissionSupportChecklist.systemSettingsURLString(for: item.id)
      #expect(string != nil, "Row \(item.id) offers a settings button with no destination.")
      #expect(string.flatMap(URL.init(string:)) != nil, "Row \(item.id) maps to an unparsable URL.")
    }

    // Rows without a button must not silently fall back to a generic pane.
    for item in PermissionSupportChecklist.defaultItems where item.systemSettingsTitle == nil {
      #expect(PermissionSupportChecklist.systemSettingsURLString(for: item.id) == nil)
    }
    #expect(PermissionSupportChecklist.systemSettingsURLString(for: "unknown") == nil)
  }

  @Test func privacyPanesAreDistinctAndMatchTheirPermission() {
    #expect(PermissionSupportChecklist.systemSettingsURLString(for: "notifications")
      == "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    #expect(PermissionSupportChecklist.systemSettingsURLString(for: "microphone")
      == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    #expect(PermissionSupportChecklist.systemSettingsURLString(for: "speech")
      == "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    #expect(PermissionSupportChecklist.systemSettingsURLString(for: "accessibility")
      == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    // A duplicate pane would send users to the wrong permission list.
    let panes = PermissionSupportChecklist.defaultItems
      .compactMap { PermissionSupportChecklist.systemSettingsURLString(for: $0.id) }
    #expect(Set(panes).count == panes.count)
  }
}
