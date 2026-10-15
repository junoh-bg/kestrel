import AppKit
import KestrelCore
import Testing

@testable import Kestrel

@Test @MainActor func nestedPathSearchFiltersParentsBeforeLimitsAndReturnsDirectChildren()
  async throws
{
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/runtime-path-" + UUID().uuidString.lowercased())
  let parent = root.appendingPathComponent("zz project/dev")
  let target = parent.appendingPathComponent("docs")
  let report = parent.appendingPathComponent("report.txt")
  let manager = FileManager.default
  try manager.createDirectory(at: target, withIntermediateDirectories: true)
  defer { try? manager.removeItem(at: root) }
  try Data("Search fixture".utf8).write(to: report)
  // More than the per-tier cap, both before parent resolution and inside its recursive scope.
  for index in 0..<170 {
    for path in ["000-other-\(index)/dev/docs", "zz project/dev/000-nested-\(index)/docs"] {
      try manager.createDirectory(
        at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }
  }
  let importer = Process()
  importer.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
  importer.arguments = [root.path]
  try importer.run()
  importer.waitUntilExit()
  var indexed = 0
  for _ in 0..<80 {
    let finder = Process()
    finder.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
    finder.arguments = ["-onlyin", root.path, "kMDItemFSName == 'docs'cd"]
    let pipe = Pipe()
    finder.standardOutput = pipe
    try finder.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    finder.waitUntilExit()
    indexed = String(decoding: data, as: UTF8.self).split(separator: "\n").count
    if indexed >= 341 { break }
    try await Task.sleep(for: .milliseconds(200))
  }
  #expect(indexed >= 341, "Spotlight fixture must be indexed before testing search")
  let search = FileSearch()
  let prefix = root.lastPathComponent + "/zz project/dev/"
  for (query, expected, kind) in [
    (prefix + "docs", target, LaunchCandidate.Kind.folder),
    (prefix + "do", target, .folder),
    (prefix + "rep", report, .file),
    (prefix + "docs/", target, .folder),
    (target.path, target, .folder),
    ("~" + target.path.dropFirst(manager.homeDirectoryForCurrentUser.path.count), target, .folder),
  ] {
    let found: [LaunchCandidate] = await withCheckedContinuation { continuation in
      search.search(query) { continuation.resume(returning: $0) }
    }
    #expect(found.map(\.url.path) == [expected.path])
    #expect(found.first?.kind == kind)
  }
  let missing: [LaunchCandidate] = await withCheckedContinuation { continuation in
    search.search(prefix + "missing/child") { continuation.resume(returning: $0) }
  }
  #expect(missing.isEmpty)
  // Cancel both parent-resolution and direct leaf phases, then replace with a new query.
  var delivered = false
  search.search(prefix + "docs") { _ in delivered = true }
  search.cancel()
  search.search(target.path) { _ in delivered = true }
  let replacement: [LaunchCandidate] = await withCheckedContinuation { continuation in
    search.search(report.path) { continuation.resume(returning: $0) }
  }
  #expect(replacement.map(\.url.path) == [report.path])
  try await Task.sleep(for: .seconds(2.3))
  #expect(!delivered)
}

@Test @MainActor func launcherShowsNestedPathsAsFoldersInNormalAndFileModes() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let launcher = LauncherWindow(
    model: try AppModel(directory: directory, pasteboard: .withUniqueName()), catalog: AppCatalog())
  let url = URL(fileURLWithPath: "/Users/test/dev/docs")
  let folder = LaunchCandidate(
    id: url.path, title: "docs", subtitle: "Folder · " + url.path, kind: .folder, url: url)
  for fileOnly in [false, true] {
    let rows = launcher.browsingRows(
      apps: [], folders: [], indexed: [folder], term: "dev/do", fileOnly: fileOnly)
    #expect(rows.first?.title == "docs")
    #expect(rows.first?.symbol == "folder")
  }
}
