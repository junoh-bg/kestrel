import Foundation
import KestrelCore

/// Filename metadata only: never opens file contents or follows directory symlinks.
enum DotfileSearch {
  struct Report: Sendable {
    let candidates: [LaunchCandidate]
    let limited: Bool
    let unreadableFolders: Int
  }

  static let skippedDirectories: Set<String> = [
    ".git", "node_modules", ".build", "dist", "build", ".venv", "venv", "__pycache__",
    ".next", ".cache", "Pods", "DerivedData",
  ]

  static func supports(_ text: String) -> Bool {
    let leaf: String
    if text.contains("/") {
      guard let path = PathSearchQuery(text) else { return false }
      leaf = path.leaf
    } else {
      leaf = text
    }
    return leaf.count >= 2 && leaf.hasPrefix(".") && leaf != ".."
  }

  static func canonicalURL(_ url: URL) -> URL {
    // Normalize aliases in parent paths while retaining a symlink's own filename.
    url.deletingLastPathComponent().resolvingSymlinksInPath()
      .appendingPathComponent(url.lastPathComponent).standardizedFileURL
  }

  static func excluded(_ url: URL, roots: [URL]) -> Bool {
    let prefixes = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path + "/" }
    guard let prefix = prefixes.filter({ url.path.hasPrefix($0) }).max(by: { $0.count < $1.count })
    else { return false }
    let relative = url.path.dropFirst(prefix.count).split(separator: "/").dropLast()
    return relative.contains { skippedDirectories.contains(String($0)) }
  }

  static func scan(
    _ text: String, roots: [URL], recursive: Bool = true,
    maxEntries: Int = 150_000, maxDuration: TimeInterval = 5
  ) -> Report {
    guard supports(text) else {
      return Report(candidates: [], limited: false, unreadableFolders: 0)
    }
    let manager = FileManager.default
    let deadline = ProcessInfo.processInfo.systemUptime + maxDuration
    let path = PathSearchQuery(text)
    let leaf = (path?.leaf ?? text).folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    var found = [String: LaunchCandidate]()
    var visitedDirectories = Set<String>()
    var entries = 0
    var limited = false
    var unreadable = 0
    // Preserve scope priority: explicit user-selected folders precede common roots.
    let orderedRoots = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
    rootsLoop: for root in orderedRoots {
      guard !Task.isCancelled else { break }
      guard visitedDirectories.insert(root.path).inserted else { continue }
      guard manager.fileExists(atPath: root.path) else { continue }
      guard
        let enumerator = manager.enumerator(
          at: root,
          includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
          options: [.skipsPackageDescendants],
          errorHandler: { _, _ in
            unreadable += 1
            return true
          })
      else {
        unreadable += 1
        continue
      }
      while let original = enumerator.nextObject() as? URL {
        guard !Task.isCancelled else { break rootsLoop }
        if entries >= maxEntries || found.count >= 5_000
          || ProcessInfo.processInfo.systemUptime >= deadline
        {
          limited = true
          break rootsLoop
        }
        entries += 1
        guard
          let values = try? original.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
          ])
        else {
          unreadable += 1
          continue
        }
        let name = original.lastPathComponent
        let directory = values.isDirectory == true && values.isSymbolicLink != true
        let skip =
          !recursive || values.isSymbolicLink == true || values.isPackage == true
          || (directory && skippedDirectories.contains(name))
        if skip {
          enumerator.skipDescendants()
        } else if directory, !visitedDirectories.insert(canonicalURL(original).path).inserted {
          enumerator.skipDescendants()
        }
        guard name.hasPrefix("."),
          name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
          ).contains(leaf)
        else { continue }
        let url = canonicalURL(original)
        let item = LaunchCandidate(
          id: url.path, title: name, subtitle: directory ? "Folder · " + url.path : url.path,
          kind: directory ? .folder : .file, url: url)
        guard path == nil || path?.relevance(of: item) != nil else { continue }
        found[url.path] = item
      }
    }
    let ordered = found.values.sorted {
      if $0.url.pathComponents.count != $1.url.pathComponents.count {
        return $0.url.pathComponents.count < $1.url.pathComponents.count
      }
      return $0.url.path < $1.url.path
    }
    return Report(
      candidates: SearchRanking.rank(ordered, query: text, events: []), limited: limited,
      unreadableFolders: unreadable)
  }
}
