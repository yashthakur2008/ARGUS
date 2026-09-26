import Foundation
import Testing
@testable import ArgusPresentation

struct GitHubUpdateCheckerTests {
  @Test func commitComparisonReportsUpdateOnlyForDifferentRemoteCommit() {
    let current = AppUpdateInfo(version: "0.1.9", build: "10", commit: "abc1234", latestEntry: nil)
    let newer = GitHubCommitSnapshot(sha: "def5678", htmlURL: URL(string: "https://github.com/yashthakur2008/ARGUS/commit/def5678")!)
    let same = GitHubCommitSnapshot(sha: "abc1234", htmlURL: URL(string: "https://github.com/yashthakur2008/ARGUS/commit/abc1234")!)

    #expect(GitHubUpdateChecker.status(current: current, remote: newer)?.kind == .updateAvailable)
    #expect(GitHubUpdateChecker.status(current: current, remote: newer)?.title == "Update available")
    #expect(GitHubUpdateChecker.status(current: current, remote: newer)?.copyCommand.contains("scripts/build-dev-app.sh") == true)
    #expect(GitHubUpdateChecker.status(current: current, remote: same)?.kind == .upToDate)
  }

  @Test func fullShaComparisonDoesNotTreatSamePrefixAsUpToDate() {
    let current = AppUpdateInfo(version: "0.1.9", build: "10", commit: "abcdef123456", latestEntry: nil)
    let remote = GitHubCommitSnapshot(sha: "abcdef999999", htmlURL: URL(string: "https://github.com/yashthakur2008/ARGUS/commit/abcdef999999")!)

    #expect(GitHubUpdateChecker.status(current: current, remote: remote)?.kind == .updateAvailable)
  }

  @Test func missingBundledCommitNeedsRebuildBeforeRemoteComparison() {
    let current = AppUpdateInfo(version: "0.1.9", build: "10", commit: nil, latestEntry: nil)
    let remote = GitHubCommitSnapshot(sha: "def5678", htmlURL: URL(string: "https://github.com/yashthakur2008/ARGUS/commit/def5678")!)

    let status = GitHubUpdateChecker.status(current: current, remote: remote)

    #expect(status?.kind == .missingLocalCommit)
    #expect(status?.title == "Rebuild ARGUS to enable update checks")
  }

  @Test func decodesGitHubCommitPayload() throws {
    let data = Data(#"{"sha":"abcdef123456","html_url":"https://github.com/yashthakur2008/ARGUS/commit/abcdef123456"}"#.utf8)

    let snapshot = try JSONDecoder().decode(GitHubCommitSnapshot.self, from: data)

    #expect(snapshot.sha == "abcdef123456")
    #expect(snapshot.htmlURL.absoluteString == "https://github.com/yashthakur2008/ARGUS/commit/abcdef123456")
  }
}
