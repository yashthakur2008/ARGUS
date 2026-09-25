import Foundation
import Testing
@testable import ArgusPresentation

struct AppChangelogTests {
  @Test func latestSectionUsesFirstVersionHeadingAndBullets() {
    let markdown = """
    # Changelog

    Intro text.

    ## v0.2.0 - 2026-09-21

    - Show the current build inside Settings.
    - Bundle the latest release notes.

    ## v0.1.9 - 2026-09-20

    - Older note.
    """

    let entry = AppChangelog.latestEntry(from: markdown)

    #expect(entry?.title == "v0.2.0 - 2026-09-21")
    #expect(entry?.items == [
      "Show the current build inside Settings.",
      "Bundle the latest release notes."
    ])
  }

  @Test func versionSummaryIncludesVersionBuildCommitAndFreshness() {
    let info = AppUpdateInfo(version: "0.2.0", build: "11", commit: "abc1234",
      latestEntry: AppChangelog.Entry(title: "v0.2.0 - 2026-09-21", items: ["Added app changelog."]))

    #expect(info.versionLine == "ARGUS 0.2.0 (11)")
    #expect(info.commitLine == "Built from commit abc1234")
    #expect(info.freshnessLine == "Showing changes bundled with this app build.")
    #expect(info.copyText.contains("ARGUS 0.2.0 (11)"))
    #expect(info.copyText.contains("Commit: abc1234"))
    #expect(info.copyText.contains("v0.2.0 - 2026-09-21"))
  }

  @Test func missingMetadataUsesExplicitUnknownLabels() {
    let info = AppUpdateInfo(version: nil, build: nil, commit: nil, latestEntry: nil)

    #expect(info.versionLine == "ARGUS version unknown")
    #expect(info.commitLine == "Build commit unavailable")
    #expect(info.freshnessLine == "This build is missing its bundled changelog. Rebuild or reinstall ARGUS from the latest app bundle.")
    #expect(info.copyText.contains("Version: unknown"))
    #expect(info.copyText.contains("Commit: unavailable"))
  }
}
