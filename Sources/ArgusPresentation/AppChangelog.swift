import Foundation

public enum AppChangelog {
  public struct Entry: Equatable, Sendable {
    public let title: String
    public let items: [String]

    public init(title: String, items: [String]) {
      self.title = title
      self.items = items
    }
  }

  public static func latestEntry(from markdown: String) -> Entry? {
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let headingIndex = lines.firstIndex(where: { $0.hasPrefix("## ") }) else { return nil }
    let title = String(lines[headingIndex].dropFirst(3)).trimmingCharacters(in: .whitespaces)
    var items: [String] = []
    for line in lines.dropFirst(headingIndex + 1) {
      if line.hasPrefix("## ") { break }
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("- ") {
        items.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
      }
    }
    return Entry(title: title, items: items)
  }
}

public struct AppUpdateInfo: Equatable, Sendable {
  public let version: String?
  public let build: String?
  public let commit: String?
  public let latestEntry: AppChangelog.Entry?

  public init(version: String?, build: String?, commit: String?, latestEntry: AppChangelog.Entry?) {
    self.version = normalized(version)
    self.build = normalized(build)
    self.commit = normalized(commit)
    self.latestEntry = latestEntry
  }

  public init(bundle: Bundle = .main) {
    let info = bundle.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String
    let build = info["CFBundleVersion"] as? String
    let commit = Self.resourceText(named: "ARGUSCommit", extension: "txt", in: bundle)
    let changelog = Self.resourceText(named: "CHANGELOG", extension: "md", in: bundle)
    self.init(version: version, build: build, commit: commit, latestEntry: changelog.flatMap(AppChangelog.latestEntry))
  }

  public var versionLine: String {
    guard let version, let build else { return "ARGUS version unknown" }
    return "ARGUS \(version) (\(build))"
  }

  public var commitLine: String {
    guard let commit else { return "Build commit unavailable" }
    return "Built from commit \(commit)"
  }

  public var freshnessLine: String {
    latestEntry == nil ? "This build is missing its bundled changelog. Rebuild or reinstall ARGUS from the latest app bundle." : "Showing changes bundled with this app build."
  }

  public var recoveryLine: String {
    latestEntry == nil ? "The running app may be older than the source checkout if Settings does not show What's new." : "This changelog came from the app bundle you are running."
  }

  public var copyText: String {
    let versionText: String
    if let version, let build {
      versionText = "ARGUS \(version) (\(build))"
    } else if let version {
      versionText = "ARGUS \(version)"
    } else {
      versionText = "Version: unknown"
    }
    var lines = [
      versionText,
      "Build: \(build ?? "unknown")",
      "Commit: \(commit ?? "unavailable")"
    ]
    if let latestEntry {
      lines.append("Changes: \(latestEntry.title)")
      lines.append(contentsOf: latestEntry.items.map { "- \($0)" })
    } else {
      lines.append("Changes: unavailable")
    }
    return lines.joined(separator: "\n")
  }

  private static func resourceText(named name: String, extension ext: String, in bundle: Bundle) -> String? {
    guard let url = bundle.url(forResource: name, withExtension: ext),
      let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    return normalized(text)
  }
}

private func normalized(_ value: String?) -> String? {
  guard let value else { return nil }
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}
