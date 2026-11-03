import Foundation
import Testing
@testable import ArgusPresentation

/// Opt-in check of a real build-dev-app.sh output. No app launch or network call.
struct PackagedUpdateIdentityTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["ARGUS_PACKAGED_APP"] != nil))
  func packagedRevisionMatchesTheSameFullRemoteCommit() throws {
    let environment = ProcessInfo.processInfo.environment
    let path = try #require(environment["ARGUS_PACKAGED_APP"])
    let expected = try #require(environment["ARGUS_EXPECTED_COMMIT"])
    #expect(expected.count == 40 || expected.count == 64)
    let bundle = try #require(Bundle(url: URL(fileURLWithPath: path)))
    let info = AppUpdateInfo(bundle: bundle)
    #expect(info.commit == expected)
    #expect(info.version != nil)
    #expect(info.latestEntry != nil)
    // Use the API's full-identity shape without a live GitHub request.
    let remote = GitHubCommitSnapshot(sha: expected,
      htmlURL: URL(string: "https://github.com/yashthakur2008/ARGUS/commit/\(expected)")!)
    let status = try #require(GitHubUpdateChecker.status(current: info, remote: remote))
    #expect(status.kind == .upToDate)
    #expect(!status.showsUpdatePrompt)
    #expect(info.copyText.contains("Commit: \(expected)"))
  }
}
