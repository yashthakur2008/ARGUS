import Foundation
import Observation

public struct GitHubCommitSnapshot: Decodable, Equatable, Sendable {
  public let sha: String
  public let htmlURL: URL

  public init(sha: String, htmlURL: URL) {
    self.sha = sha
    self.htmlURL = htmlURL
  }

  enum CodingKeys: String, CodingKey {
    case sha
    case htmlURL = "html_url"
  }
}

public enum GitHubUpdateKind: Equatable, Sendable {
  case upToDate
  case updateAvailable
  case missingLocalCommit
}

public struct GitHubUpdateStatus: Equatable, Sendable {
  public let kind: GitHubUpdateKind
  public let title: String
  public let message: String
  public let currentCommit: String?
  public let latestCommit: String?
  public let latestCommitURL: URL?
  public let copyCommand: String

  public var showsUpdatePrompt: Bool { kind == .updateAvailable || kind == .missingLocalCommit }
}

public enum GitHubUpdateChecker {
  public static let repository = "yashthakur2008/ARGUS"
  public static let branch = "feat/stress-evidence"
  public static let updatePromptBranch = "feat/github-update-prompt"
  public static let latestCommitURL = URL(string: "https://api.github.com/repos/\(repository)/commits/\(branch)")!
  public static let pullRequestURL = URL(string: "https://github.com/yashthakur2008/ARGUS/pulls?q=is%3Apr+head%3A\(updatePromptBranch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updatePromptBranch)")!
  public static let rebuildCommand = "ARGUS_SWIFT=/Applications/Xcode_16.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift bash scripts/build-dev-app.sh"

  public static func status(current: AppUpdateInfo, remote: GitHubCommitSnapshot) -> GitHubUpdateStatus? {
    guard let local = current.commit else {
      return GitHubUpdateStatus(kind: .missingLocalCommit,
        title: "Rebuild ARGUS to enable update checks",
        message: "This app bundle does not include ARGUSCommit.txt, so it cannot compare itself with GitHub. Rebuild or reinstall the latest app bundle.",
        currentCommit: nil, latestCommit: short(remote.sha), latestCommitURL: remote.htmlURL,
        copyCommand: rebuildCommand)
    }
    let localFull = normalizedSHA(local)
    let remoteFull = normalizedSHA(remote.sha)
    let localShort = short(localFull)
    let remoteShort = short(remoteFull)
    if localFull.caseInsensitiveCompare(remoteFull) == .orderedSame {
      return GitHubUpdateStatus(kind: .upToDate,
        title: "ARGUS is up to date",
        message: "This app was built from the latest checked GitHub commit.",
        currentCommit: localShort, latestCommit: remoteShort, latestCommitURL: remote.htmlURL,
        copyCommand: rebuildCommand)
    }
    return GitHubUpdateStatus(kind: .updateAvailable,
      title: "Update available",
      message: "A newer ARGUS commit is available on GitHub. View the PR or rebuild the latest app bundle to update this Mac.",
      currentCommit: localShort, latestCommit: remoteShort, latestCommitURL: remote.htmlURL,
      copyCommand: rebuildCommand)
  }

  public static func short(_ sha: String) -> String {
    String(normalizedSHA(sha).prefix(7))
  }

  public static func normalizedSHA(_ sha: String) -> String {
    sha.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

@MainActor @Observable
public final class GitHubUpdateModel {
  public private(set) var status: GitHubUpdateStatus?
  public private(set) var isChecking = false
  public private(set) var errorMessage: String?

  private let current: () -> AppUpdateInfo
  private let fetch: @Sendable () async throws -> GitHubCommitSnapshot

  public init(current: @escaping () -> AppUpdateInfo = { AppUpdateInfo() },
    fetch: @escaping @Sendable () async throws -> GitHubCommitSnapshot = GitHubUpdateModel.fetchLatestCommit) {
    self.current = current
    self.fetch = fetch
  }

  public func check() async {
    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }
    do {
      status = GitHubUpdateChecker.status(current: current(), remote: try await fetch())
      errorMessage = nil
    } catch {
      errorMessage = "Could not check GitHub for updates. Try again when this Mac is online."
    }
  }

  public static func fetchLatestCommit() async throws -> GitHubCommitSnapshot {
    var request = URLRequest(url: GitHubUpdateChecker.latestCommitURL)
    request.timeoutInterval = 6
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("ARGUS", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(GitHubCommitSnapshot.self, from: data)
  }
}
