import Darwin
import Foundation

struct SearchAccessReport {
  enum State: Equatable { case readable, denied, unavailable }
  struct Entry {
    let url: URL
    let state: State
  }
  let entries: [Entry]
  var summary: String {
    let denied = entries.filter { $0.state == .denied }.map { $0.url.lastPathComponent }
    let unavailable = entries.filter { $0.state == .unavailable }.map { $0.url.lastPathComponent }
    var issues = [String]()
    if !denied.isEmpty {
      issues.append(
        "Access blocked: " + denied.joined(separator: ", ")
          + ". Enable access in macOS, then check again.")
    }
    if !unavailable.isEmpty {
      issues.append(
        "Could not check: " + unavailable.joined(separator: ", ")
          + ". The location may be missing or offline.")
    }
    if !issues.isEmpty { return issues.joined(separator: " ") }
    return
      "Folder listing check passed. Missing results may be excluded from Spotlight or not indexed yet."
  }
  var detail: String {
    entries.map { entry in
      let state: String
      switch entry.state {
      case .readable: state = "Readable"
      case .denied: state = "Blocked"
      case .unavailable: state = "Unavailable"
      }
      return entry.url.lastPathComponent + ": " + state
    }.joined(separator: " · ")
  }
  static func inspect(
    _ urls: [URL],
    readDirectory: (URL) throws -> Void = { url in
      try checkDirectoryListing(url)
    }
  ) -> SearchAccessReport {
    var seen = Set<String>()
    return SearchAccessReport(
      entries: urls.filter { seen.insert($0.standardizedFileURL.path).inserted }.map { url in
        do {
          try readDirectory(url)
          return Entry(url: url, state: .readable)
        } catch {
          return Entry(url: url, state: permissionDenied(error as NSError) ? .denied : .unavailable)
        }
      })
  }
  static func checkDirectoryListing(_ url: URL) throws {
    guard let directory = opendir(url.path) else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer { closedir(directory) }
    errno = 0
    // Test a single entry; no names or file contents are retained.
    if readdir(directory) == nil && errno != 0 {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
  }
  private static func permissionDenied(_ error: NSError) -> Bool {
    if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
      return true
    }
    if error.domain == NSPOSIXErrorDomain && [1, 13].contains(error.code) { return true }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
      return permissionDenied(underlying)
    }
    return false
  }
}
