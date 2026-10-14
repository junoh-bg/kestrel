import XCTest

@testable import KestrelCore

final class KestrelCoreTests: XCTestCase {
  private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

  func testCalculatorHonorsPrecedenceParenthesesUnaryAndExponentiation() {
    XCTAssertEqual(Calculator.evaluate("2 + 3 * 4"), 14)
    XCTAssertEqual(Calculator.evaluate("-(2 + 3) * 4"), -20)
    XCTAssertEqual(Calculator.evaluate("2 ^ 3 ^ 2"), 512)
    XCTAssertEqual(Calculator.evaluate(".5 + 1.25"), 1.75)
  }

  func testCalculatorRejectsInvalidDangerousAndOversizedExpressions() {
    XCTAssertNil(Calculator.evaluate("1 / 0"))
    XCTAssertNil(Calculator.evaluate("sqrt(4)"))
    XCTAssertNil(Calculator.evaluate("1 +"))
    XCTAssertNil(
      Calculator.evaluate(
        String(repeating: "(", count: 33) + "1" + String(repeating: ")", count: 33)))
    XCTAssertNil(Calculator.evaluate(String(repeating: "1", count: 513)))
  }

  func testGoogleSearchEncodesQueryAsSingleQParameter() throws {
    let url = try XCTUnwrap(GoogleSearch.url(for: "Swift & tea / 한글"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.scheme, "https")
    XCTAssertEqual(components.host, "www.google.com")
    XCTAssertEqual(components.path, "/search")
    XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: "Swift & tea / 한글")])
  }

  func testRankingPrefersExactAndPrefixTextMatchesBeforeUsage() {
    let candidates = [
      candidate("mail", "Mail"),
      candidate("mailer", "Mailer"),
      candidate("email", "Email"),
    ]
    let events = [
      UsageEvent(id: "email", query: "mail", date: epoch),
      UsageEvent(id: "email", query: "mail", date: epoch),
    ]
    XCTAssertEqual(
      SearchRanking.rank(candidates, query: "mail", events: events, now: epoch).map(\.id),
      ["mail", "mailer", "email"]
    )
  }

  func testRankingUsesQueryUsageThenRecentUsageThenOriginalOrderWithinTextTier() {
    let candidates = [
      candidate("first", "XBeta"), candidate("second", "YBeta"), candidate("third", "ZBeta"),
    ]
    let events = [
      UsageEvent(id: "second", query: "be", date: epoch),
      UsageEvent(id: "third", query: "other", date: epoch),
      UsageEvent(id: "third", query: "other", date: epoch),
    ]
    XCTAssertEqual(
      SearchRanking.rank(candidates, query: "be", events: events, now: epoch).map(\.id),
      ["second", "third", "first"])
  }

  func testRankingLargeInputKeepsUsageSemanticsAndDeterministicOrder() {
    let candidates = (0..<2_000).map { candidate("id-\($0)", "Item \(String(format: "%04d", $0))") }
    var events = [UsageEvent]()
    events += Array(repeating: UsageEvent(id: "id-1300", query: "item", date: epoch), count: 3)
    events += Array(repeating: UsageEvent(id: "id-900", query: "other", date: epoch), count: 5)
    events += Array(
      repeating: UsageEvent(
        id: "id-1900", query: "item", date: epoch.addingTimeInterval(-8 * 86_400)), count: 20)

    let ranked = SearchRanking.rank(candidates, query: "item", events: events, now: epoch)
    XCTAssertEqual(ranked.count, candidates.count)
    XCTAssertEqual(Array(ranked.prefix(3)).map(\.id), ["id-1900", "id-1300", "id-900"])
    XCTAssertEqual(ranked.last?.id, "id-1999")
  }

  func testRankingIsCaseAndDiacriticInsensitiveAndAllowsSubsequences() {
    let candidates = [
      candidate("cafe", "Café"), candidate("code", "Code Editor"), candidate("clock", "Clock"),
    ]
    XCTAssertEqual(
      SearchRanking.rank(candidates, query: "cfe", events: [], now: epoch).map(\.id), ["cafe"])
    XCTAssertEqual(
      SearchRanking.rank(candidates, query: "CAFE", events: [], now: epoch).map(\.id), ["cafe"])
  }

  func testClipboardHistoryRejectsInvalidDeduplicatesAndPrunes() {
    let old = ClipboardItem(text: "old", date: epoch.addingTimeInterval(-31 * 86_400))
    let prior = ClipboardItem(text: "again", date: epoch.addingTimeInterval(-10))
    let result = ClipboardHistory.adding(
      "again", to: [old, prior, ClipboardItem(text: "keep", date: epoch)], now: epoch, limit: 2)
    XCTAssertEqual(result.map(\.text), ["again", "keep"])
    XCTAssertEqual(ClipboardHistory.adding("", to: result, now: epoch), result)
    XCTAssertEqual(
      ClipboardHistory.adding(String(repeating: "a", count: 100_001), to: result, now: epoch),
      result)
  }

  func testClipboardHistoryDropsInvalidExistingRecordsDuringNormalization() {
    let oversized = ClipboardItem(text: String(repeating: "a", count: 100_001), date: epoch)
    let result = ClipboardHistory.adding(
      "",
      to: [
        ClipboardItem(text: "", date: epoch), oversized, ClipboardItem(text: "keep", date: epoch),
      ], now: epoch)
    XCTAssertEqual(result.map(\.text), ["keep"])
  }

  func testStoredStateRoundTripsAndStateStoreUsesPrivateAtomicStorage() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try StateStore(directory: directory)
    let state = StoredState(
      history: [ClipboardItem(text: "clip", date: epoch)],
      snippets: [Snippet(title: "Greeting", keyword: "hi", text: "Hello")],
      usage: [UsageEvent(id: "mail", query: "ma", date: epoch)],
      captureEnabled: true
    )
    try store.save(state)
    XCTAssertEqual(try store.load(), state)
    try store.save(StoredState(captureEnabled: false))
    XCTAssertEqual(try store.load(), StoredState())
    let attributes = try FileManager.default.attributesOfItem(
      atPath: directory.appendingPathComponent("state.json").path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
  }

  func testStateStoreReturnsEmptyForMissingFileAndPreservesCorruptFile() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try StateStore(directory: directory)
    XCTAssertEqual(try store.load(), StoredState())
    let file = directory.appendingPathComponent("state.json")
    try Data("not json".utf8).write(to: file)
    XCTAssertThrowsError(try store.load())
    XCTAssertEqual(try String(contentsOf: file), "not json")
  }

  func testStateStoreCleansTemporaryFileWhenReplacementFails() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try StateStore(directory: directory)
    let file = directory.appendingPathComponent("state.json")
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    let sentinel = file.appendingPathComponent("sentinel")
    try Data("preserve me".utf8).write(to: sentinel)

    XCTAssertThrowsError(try store.save(StoredState(captureEnabled: true)))
    XCTAssertEqual(try String(contentsOf: sentinel), "preserve me")
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["state.json"])
  }

  private func candidate(_ id: String, _ title: String) -> LaunchCandidate {
    LaunchCandidate(
      id: id, title: title, subtitle: "", kind: .application, url: URL(fileURLWithPath: "/\(id)"))
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
}
