import Foundation

/// Slash-separated names match adjacent directories; only the final name may be partial.
public struct PathSearchQuery: Sendable {
  public let leaf: String
  public let foldersOnly: Bool
  public let explicitParent: URL?
  private let parents: [String]

  public var parentName: String? { parents.last }

  public init?(_ text: String) {
    var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard input.contains("/"), !input.contains("://"), input.utf8.count <= 4096 else { return nil }
    if input.hasPrefix("~/") {
      input = FileManager.default.homeDirectoryForCurrentUser.path + input.dropFirst()
    }
    let absolute = input.hasPrefix("/")
    foldersOnly = input.hasSuffix("/")
    var components = input.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if absolute { components.removeFirst() }
    if foldersOnly { components.removeLast() }
    guard !components.isEmpty,
      components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0 != "~" })
    else { return nil }
    leaf = components.removeLast()
    parents = components
    explicitParent = absolute ? URL(fileURLWithPath: "/" + components.joined(separator: "/")) : nil
  }

  public func matchesParent(_ url: URL) -> Bool {
    let actual = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
    guard actual.count >= parents.count,
      explicitParent == nil || actual.count == parents.count
    else { return false }
    return zip(actual.suffix(parents.count), parents).allSatisfy {
      Self.normalize($0) == Self.normalize($1)
    }
  }

  public func relevance(of candidate: LaunchCandidate) -> Int? {
    guard !foldersOnly || candidate.kind == .folder,
      matchesParent(candidate.url.deletingLastPathComponent())
    else {
      return nil
    }
    let name = Self.normalize(candidate.url.lastPathComponent)
    let term = Self.normalize(leaf)
    if name == term { return 4 }
    return name.hasPrefix(term) ? 3 : nil
  }

  private static func normalize(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }
}
