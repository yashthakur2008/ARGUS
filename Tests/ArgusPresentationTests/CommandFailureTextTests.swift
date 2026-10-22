import Foundation
import Testing
import ArgusCore
import ArgusStore
@testable import ArgusPresentation

struct CommandFailureTextTests {
  @MainActor @Test func unrecognizedCommandExplainsItselfWithoutSwiftSyntax() {
    let text = CommandFailureText.message(for: CoreError.unsupportedCommand,
      examples: AppModel.examples)

    #expect(!text.contains("unsupportedCommand"))
    #expect(text.contains("did not recognize"))
    // The guidance is only useful if it shows a phrase that actually parses.
    #expect(text.contains("remind me to"))
  }

  @Test func everyCoreAndStoreFailureReadsAsASentence() {
    let errors: [any Error] = [
      CoreError.unsupportedCommand, CoreError.invalidTitle, CoreError.invalidDate,
      CoreError.invalidDuration, CoreError.invalidOffsets, CoreError.invalidRecurrence,
      CoreError.invalidSnooze, CoreError.invalidRevision, CoreError.invalidQuietHours,
      CoreError.invalidHorizon, CoreError.notificationLimitExceeded,
      CoreError.invalidTimeZone("Mars/Olympus"),
      StoreError.sqlite(code: 11, message: "database disk image is malformed"),
      StoreError.conflict, StoreError.corruption("bad page"), StoreError.unsupportedSchema(99),
      StoreError.noticeNotFound("x"), StoreError.noticeDismissed("x"),
      StoreError.noticeNoLongerApplicable("x"), StoreError.invalidSnooze,
      StoreError.activeSnoozeConflict, StoreError.revisionOverflow,
    ]

    for error in errors {
      let reason = CommandFailureText.reason(for: error)
      #expect(reason.hasSuffix("."), "Not a sentence: \(reason)")
      #expect(!reason.contains("("), "Leaks enum payload syntax: \(reason)")
      // Lowercase camel case is the signature of a leaked Swift case name.
      // Real product names such as macOS are legitimate and excluded.
      let deCased = reason.replacingOccurrences(of: "macOS", with: "macos")
      #expect(deCased.range(of: "[a-z][A-Z]", options: .regularExpression) == nil,
        "Leaks a Swift case name: \(reason)")
      #expect(reason.first.map(\.isUppercase) == true, "Not capitalized: \(reason)")
    }
  }

  @Test func unknownErrorsStillAvoidRawInterpolation() {
    struct Mystery: Error {}

    let reason = CommandFailureText.reason(for: Mystery())

    #expect(!reason.contains("Mystery"))
    #expect(reason.hasSuffix("."))
  }
}
