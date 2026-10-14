import Foundation

public struct LaunchCandidate: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case application, file, folder }

  public let id: String
  public let title: String
  public let subtitle: String
  public let kind: Kind
  public let url: URL

  public init(id: String, title: String, subtitle: String, kind: Kind, url: URL) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.kind = kind
    self.url = url
  }
}

public struct UsageEvent: Codable, Equatable, Sendable {
  public let id: String
  public let query: String
  public let date: Date

  public init(id: String, query: String, date: Date) {
    self.id = id
    self.query = query
    self.date = date
  }
}

public enum SearchRanking {
  /// Results are ordered by exact/prefix/contains/subsequence title relevance,
  /// then query-specific use, seven-day use, and their incoming order.
  public static func rank(
    _ candidates: [LaunchCandidate], query: String, events: [UsageEvent], now: Date = Date()
  ) -> [LaunchCandidate] {
    let normalizedQuery = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
    let cutoff = now.addingTimeInterval(-7 * 86_400)
    var queryUses = [String: [String: Int]]()
    var recentUses = [String: Int]()
    for event in events {
      let normalizedEventQuery = normalize(event.query)
      var usesByQuery = queryUses[event.id, default: [:]]
      usesByQuery[normalizedEventQuery, default: 0] += 1
      queryUses[event.id] = usesByQuery
      if event.date >= cutoff && event.date <= now {
        recentUses[event.id, default: 0] += 1
      }
    }
    let scored = candidates.enumerated().compactMap {
      index, candidate -> (LaunchCandidate, Int, Int, Int, Int)? in
      guard let relevance = relevance(of: normalize(candidate.title), for: normalizedQuery) else {
        return nil
      }
      return (
        candidate, relevance, queryUses[candidate.id]?[normalizedQuery] ?? 0,
        recentUses[candidate.id] ?? 0, index
      )
    }
    return scored.sorted {
      if $0.1 != $1.1 { return $0.1 > $1.1 }
      if $0.2 != $1.2 { return $0.2 > $1.2 }
      if $0.3 != $1.3 { return $0.3 > $1.3 }
      return $0.4 < $1.4
    }.map(\.0)
  }

  private static func normalize(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }

  private static func relevance(of title: String, for query: String) -> Int? {
    guard !query.isEmpty else { return 0 }
    if title == query { return 4 }
    if title.hasPrefix(query) { return 3 }
    if title.contains(query) { return 2 }
    var position = title.startIndex
    for character in query {
      guard let found = title[position...].firstIndex(of: character) else { return nil }
      position = title.index(after: found)
    }
    return 1
  }
}

public enum Calculator {
  public static func evaluate(_ expression: String) -> Double? {
    guard expression.utf8.count <= 512 else { return nil }
    var parser = Parser(expression)
    guard let value = parser.expression(), parser.isAtEnd(), value.isFinite else { return nil }
    return value
  }

  private struct Parser {
    let characters: [Character]
    var index = 0
    var parenthesisDepth = 0

    init(_ input: String) { characters = Array(input) }

    mutating func isAtEnd() -> Bool {
      skipWhitespace()
      return index == characters.count
    }

    mutating func expression() -> Double? {
      guard var value = product() else { return nil }
      while true {
        if consume("+") {
          guard let rhs = product() else { return nil }
          value += rhs
        } else if consume("-") {
          guard let rhs = product() else { return nil }
          value -= rhs
        } else {
          break
        }
        guard value.isFinite else { return nil }
      }
      return value
    }

    mutating func product() -> Double? {
      guard var value = unary() else { return nil }
      while true {
        if consume("*") {
          guard let rhs = unary() else { return nil }
          value *= rhs
        } else if consume("/") {
          guard let rhs = unary(), rhs != 0 else { return nil }
          value /= rhs
        } else {
          break
        }
        guard value.isFinite else { return nil }
      }
      return value
    }

    mutating func unary() -> Double? {
      if consume("+") { return unary() }
      if consume("-") { return unary().map(-) }
      return power()
    }

    mutating func power() -> Double? {
      guard let base = primary() else { return nil }
      guard consume("^") else { return base }
      guard let exponent = unary() else { return nil }
      let value = Foundation.pow(base, exponent)
      return value.isFinite ? value : nil
    }

    mutating func primary() -> Double? {
      if consume("(") {
        parenthesisDepth += 1
        defer { parenthesisDepth -= 1 }
        guard parenthesisDepth <= 32, let value = expression(), consume(")") else { return nil }
        return value
      }
      return number()
    }

    mutating func number() -> Double? {
      skipWhitespace()
      let start = index
      var hasDigit = false
      var hasDecimal = false
      while index < characters.count {
        let character = characters[index]
        if character.isNumber && character.isASCII {
          hasDigit = true
          index += 1
        } else if character == "." && !hasDecimal {
          hasDecimal = true
          index += 1
        } else {
          break
        }
      }
      guard hasDigit else {
        index = start
        return nil
      }
      return Double(String(characters[start..<index]))
    }

    mutating func consume(_ expected: Character) -> Bool {
      skipWhitespace()
      guard index < characters.count, characters[index] == expected else { return false }
      index += 1
      return true
    }

    mutating func skipWhitespace() {
      while index < characters.count && characters[index].isWhitespace { index += 1 }
    }
  }
}

public enum GoogleSearch {
  public static func url(for query: String) -> URL? {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.google.com"
    components.path = "/search"
    components.queryItems = [URLQueryItem(name: "q", value: query)]
    return components.url
  }
}

public struct ClipboardItem: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let text: String
  public let date: Date

  public init(id: UUID = UUID(), text: String, date: Date = Date()) {
    self.id = id
    self.text = text
    self.date = date
  }
}

public struct Snippet: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let title: String
  public let keyword: String
  public let text: String

  public init(id: UUID = UUID(), title: String, keyword: String, text: String) {
    self.id = id
    self.title = title
    self.keyword = keyword
    self.text = text
  }
}

public struct StoredState: Codable, Equatable, Sendable {
  public var history: [ClipboardItem]
  public var snippets: [Snippet]
  public var usage: [UsageEvent]
  public var captureEnabled: Bool
  public var themeID: String?

  public init(
    history: [ClipboardItem] = [], snippets: [Snippet] = [], usage: [UsageEvent] = [],
    captureEnabled: Bool = false, themeID: String? = nil
  ) {
    self.history = history
    self.snippets = snippets
    self.usage = usage
    self.captureEnabled = captureEnabled
    self.themeID = themeID
  }
}

public final class StateStore {
  public let directory: URL
  private let fileName = "state.json"

  public init(directory: URL) throws {
    self.directory = directory
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }

  public func load() throws -> StoredState {
    let file = directory.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: file.path) else { return StoredState() }
    return try JSONDecoder().decode(StoredState.self, from: Data(contentsOf: file))
  }

  public func save(_ state: StoredState) throws {
    let file = directory.appendingPathComponent(fileName)
    if FileManager.default.fileExists(atPath: file.path) {
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular else {
        throw CocoaError(.fileWriteInvalidFileName)
      }
    }
    let temporary = directory.appendingPathComponent(".state-\(UUID().uuidString).tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }
    let data = try JSONEncoder().encode(state)
    try data.write(to: temporary, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
    if FileManager.default.fileExists(atPath: file.path) {
      _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: file)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }
}

public enum ClipboardHistory {
  public static func adding(
    _ text: String, to items: [ClipboardItem], now: Date = Date(), limit: Int = 100,
    maxAge: TimeInterval = 30 * 86_400
  ) -> [ClipboardItem] {
    guard limit > 0 else { return [] }
    let cutoff = now.addingTimeInterval(-max(0, maxAge))
    var seen = Set<String>()
    var result: [ClipboardItem] = []
    let validNewItem = !text.isEmpty && text.utf8.count <= 100_000
    let source = validNewItem ? [ClipboardItem(text: text, date: now)] + items : items
    for item in source where item.date >= cutoff {
      guard !item.text.isEmpty, item.text.utf8.count <= 100_000 else { continue }
      guard seen.insert(item.text).inserted else { continue }
      result.append(item)
      if result.count == limit { break }
    }
    return result
  }
}
