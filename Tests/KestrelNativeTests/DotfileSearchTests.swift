import AppKit
import KestrelCore
import Testing

@testable import Kestrel

@Suite(.serialized) @MainActor struct DotfileSearchTests {
  private func fixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for path in [
      "project-one/.env", "project-two/backend/.env", "project-two/.env.local",
      "project-two/.config/.env", "project-two/.git/internal/.env",
      "project-two/node_modules/dependency/.env",
    ] {
      let file = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: file)
    }
    return root
  }

  private func results(_ search: FileSearch, _ query: String, under root: URL) async
    -> [LaunchCandidate]
  {
    let found: [LaunchCandidate] = await withCheckedContinuation { continuation in
      search.search(query) { continuation.resume(returning: $0) }
    }
    let prefix = root.resolvingSymlinksInPath().path + "/"
    return found.filter { $0.url.resolvingSymlinksInPath().path.hasPrefix(prefix) }
  }

  @Test func findsUnindexedDotfilesByFilenameWithoutReadingContents() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let locked = root.appendingPathComponent("project-one/.env")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    let search = FileSearch(filenameRoots: [root])
    let found = await results(search, ".env", under: root)
    let paths = found.map { $0.url.resolvingSymlinksInPath().path }
    let expected = [
      "project-one/.env", "project-two/backend/.env", "project-two/.config/.env",
      "project-two/.env.local",
    ].map { root.appendingPathComponent($0).resolvingSymlinksInPath().path }
    #expect(Set(paths) == Set(expected))
    #expect(found.prefix(3).allSatisfy { $0.title == ".env" })
    #expect(found.allSatisfy { $0.kind == .file })
  }

  @Test func nestedAndAbsoluteDotfilePathsFindUnindexedFiles() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let search = FileSearch(filenameRoots: [root])
    let target = root.appendingPathComponent("project-two/backend/.env").resolvingSymlinksInPath()
      .path
    for query in ["project-two/backend/.env", target] {
      let found = await results(search, query, under: root)
      #expect(found.map { $0.url.resolvingSymlinksInPath().path } == [target])
    }
  }

  @Test func overlappingScopesAreDeduplicatedAndSymlinkLoopsAreNotFollowed() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("project-one/loop"), withDestinationURL: root)
    let search = FileSearch(filenameRoots: [root, root.appendingPathComponent("project-one")])
    search.additionalScopes = [root]
    let found = await results(search, ".env", under: root)
    #expect(found.count == 4)
    #expect(Set(found.map(\.id)).count == 4)
    #expect(!found.contains { $0.url.path.contains("/loop/") })
  }

  @Test func cancelAndReplacementCannotDeliverOldDotfileResults() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appendingPathComponent("project-one/.gitignore"))
    let search = FileSearch(filenameRoots: [root])
    var deliveries = 0
    search.search(".env") { _ in deliveries += 1 }
    search.cancel()
    search.search(".env") { _ in deliveries += 1 }
    let found = await results(search, ".gitignore", under: root)
    #expect(found.count == 1)
    try await Task.sleep(for: .milliseconds(100))
    #expect(deliveries == 0)
  }
}

@Test func dotfileScanReportsLimitsAndRejectsOrdinaryQueries() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try Data().write(to: root.appendingPathComponent(".env"))
  let limited = DotfileSearch.scan(".env", roots: [root], maxEntries: 0)
  #expect(limited.limited)
  #expect(limited.candidates.isEmpty)
  let expired = DotfileSearch.scan(".env", roots: [root], maxDuration: 0)
  #expect(expired.limited)
  #expect(!DotfileSearch.supports("env"))
  #expect(!DotfileSearch.supports(".."))
  #expect(!DotfileSearch.supports("dev/../.env"))
  #expect(DotfileSearch.scan("env", roots: [root]).candidates.isEmpty)
}

@Test @MainActor func dotfileResultsAreScrollableBeyondTwelveMatches() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let launcher = LauncherWindow(
    model: try AppModel(directory: root, pasteboard: .withUniqueName()), catalog: AppCatalog())
  let matches = (0..<30).map { index in
    let url = root.appendingPathComponent("project-\(index)/.env")
    return LaunchCandidate(id: url.path, title: ".env", subtitle: url.path, kind: .file, url: url)
  }
  let rows = launcher.browsingRows(
    apps: [], folders: [], indexed: matches, term: ".env", fileOnly: true)
  #expect(rows.count == 30)
}

@Test func dotfileScanKeepsFileSymlinkNamesAndFindsDotDirectories() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(
    at: root.appendingPathComponent(".config"), withIntermediateDirectories: true)
  try Data().write(to: root.appendingPathComponent("target"))
  try FileManager.default.createSymbolicLink(
    at: root.appendingPathComponent(".env.link"),
    withDestinationURL: root.appendingPathComponent("target"))
  let links = DotfileSearch.scan(".env", roots: [root]).candidates
  #expect(links.map(\.title) == [".env.link"])
  #expect(links.first?.url.lastPathComponent == ".env.link")
  let folders = DotfileSearch.scan(".config/", roots: [root]).candidates
  #expect(folders.map(\.title) == [".config"])
  #expect(folders.first?.kind == .folder)
}

@Test @MainActor func selectedFolderOverridesAnAncestorDependencyExclusion() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let selected = root.appendingPathComponent("node_modules/selected-project")
  try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
  let file = selected.appendingPathComponent(".env")
  try Data().write(to: file)
  let direct = DotfileSearch.scan(".env", roots: [selected, root])
  #expect(direct.candidates.contains { $0.url.lastPathComponent == ".env" })
  let search = FileSearch(filenameRoots: [root])
  search.additionalScopes = [selected]
  let found: [LaunchCandidate] = await withCheckedContinuation { continuation in
    search.search(".env") { continuation.resume(returning: $0) }
  }
  #expect(
    found.contains { $0.url.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path })
}
