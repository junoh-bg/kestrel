import AppKit

@MainActor final class SearchFolderAccess {
  private let file: URL
  private var bookmarks = [Data]()
  private var storageBlocked = false
  private var scopedURLs = [URL]()
  private(set) var urls = [URL]()
  private(set) var error: String?
  init(directory: URL) {
    file = directory.appendingPathComponent("search-folders.json")
    if FileManager.default.fileExists(atPath: file.path) {
      do {
        bookmarks = try JSONDecoder().decode([Data].self, from: Data(contentsOf: file))
        activate()
      } catch {
        storageBlocked = true
        self.error =
          "Saved search-folder access could not be read. The existing search-folders.json file was preserved; recover or move it aside before adding folders, then restart Kestrel."
      }
    }
  }
  func add(_ url: URL) throws {
    guard !storageBlocked else {
      throw NSError(
        domain: "Kestrel", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: error ?? "Saved search-folder access needs recovery."
        ])
    }
    let bookmark = try url.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    var stale = false
    let resolved = try URL(
      resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
      bookmarkDataIsStale: &stale)
    guard !stale else {
      throw NSError(
        domain: "Kestrel", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Folder access expired. Choose it again."])
    }
    let started = resolved.startAccessingSecurityScopedResource()
    var retained = false
    defer { if started && !retained { resolved.stopAccessingSecurityScopedResource() } }
    // An unsandboxed app can already have access without a security-scope token.
    // Verify actual directory access instead of treating a false token as denial.
    try SearchAccessReport.checkDirectoryListing(resolved)
    let next =
      bookmarks.filter { data in
        var oldStale = false
        let old = try? URL(
          resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
          bookmarkDataIsStale: &oldStale)
        return old?.standardizedFileURL.path != resolved.standardizedFileURL.path
      } + [bookmark]
    let encoded = try JSONEncoder().encode(next)
    try encoded.write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    bookmarks = next
    for old in scopedURLs where old.path == resolved.path {
      old.stopAccessingSecurityScopedResource()
    }
    scopedURLs.removeAll { $0.path == resolved.path }
    urls.removeAll { $0.path == resolved.path }
    urls.append(resolved)
    if started {
      scopedURLs.append(resolved)
      retained = true
    }
    error = nil
  }

  deinit { for url in scopedURLs { url.stopAccessingSecurityScopedResource() } }
  private func activate() {
    for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
    scopedURLs = []
    urls = []
    var seen = Set<String>()
    for data in bookmarks.reversed() {
      var stale = false
      guard
        let url = try? URL(
          resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
          bookmarkDataIsStale: &stale)
      else {
        error = "Some search-folder access expired. Choose your folder again."
        continue
      }
      if seen.contains(url.path) { continue }
      guard !stale else {
        error = "Some search-folder access expired. Choose your folder again."
        continue
      }
      let started = url.startAccessingSecurityScopedResource()
      do { try SearchAccessReport.checkDirectoryListing(url) } catch {
        if started { url.stopAccessingSecurityScopedResource() }
        self.error =
          "Could not restore search-folder access. Choose your folder again or enable Full Disk Access."
        continue
      }
      if started { scopedURLs.append(url) }
      seen.insert(url.path)
      urls.append(url)
    }
  }
}
