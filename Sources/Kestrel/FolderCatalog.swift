import Foundation
import KestrelCore

@MainActor enum FolderCatalog {
  static func displayPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if url.path == home { return "~" }
    if url.path.hasPrefix(home + "/") { return "~" + url.path.dropFirst(home.count) }
    return url.path
  }

  static func candidates(additionalScopes: [URL]) -> [LaunchCandidate] {
    let manager = FileManager.default
    var urls = [manager.homeDirectoryForCurrentUser]
    for directory: FileManager.SearchPathDirectory in [
      .downloadsDirectory, .desktopDirectory, .documentDirectory, .picturesDirectory,
      .musicDirectory, .moviesDirectory,
    ] {
      urls += manager.urls(for: directory, in: .userDomainMask)
    }
    urls += additionalScopes
    var seen = Set<String>()
    return urls.compactMap { original in
      let url = original.standardizedFileURL
      guard seen.insert(url.path).inserted else { return nil }
      let title = url == manager.homeDirectoryForCurrentUser ? "Home" : url.lastPathComponent
      let path = displayPath(url)
      return LaunchCandidate(
        id: url.path, title: title, subtitle: "Folder · " + path, kind: .folder, url: url)
    }
  }
}
