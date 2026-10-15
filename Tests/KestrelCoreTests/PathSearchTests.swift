import Foundation
import XCTest

@testable import KestrelCore

final class PathSearchTests: XCTestCase {
  private func item(_ path: String, kind: LaunchCandidate.Kind = .folder) -> LaunchCandidate {
    let url = URL(fileURLWithPath: path)
    return LaunchCandidate(
      id: path, title: url.lastPathComponent, subtitle: path, kind: kind, url: url)
  }

  func testPathSearchUsesAdjacentParentComponentsAndRanksExactLeafFirst() {
    let paths = [
      "/Users/test/dev/docs-old", "/Users/test/other/docs", "/Users/test/mydev/docs",
      "/Users/test/dev/project/docs", "/Users/test/dev/docs", "/Users/test/dev/mydocs",
    ]
    XCTAssertEqual(
      SearchRanking.rank(paths.map { item($0) }, query: "dev/docs", events: []).map(\.id),
      ["/Users/test/dev/docs", "/Users/test/dev/docs-old"])
  }

  func testPathSearchSupportsMultipleParentsFilesSpacesAndUnicode() {
    let paths = [
      "/Users/test/Dev/My Project/문서/Report.txt", "/Users/test/Dev/Other/문서/Report.txt",
    ]
    XCTAssertEqual(
      SearchRanking.rank(
        paths.map { item($0, kind: .file) }, query: "dev/My Project/문서/rep", events: []
      ).map(\.id),
      [paths[0]])
    XCTAssertEqual(
      SearchRanking.rank([item("/Users/test/Café/docs")], query: "CAFE/do", events: []).count, 1)
  }

  func testPathSearchUnderstandsHomeAndAbsoluteAnchors() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let paths = [home + "/Desktop/dev/docs", "/Volumes/Backup" + home + "/Desktop/dev/docs"]
    for query in ["~/Desktop/dev/do", home + "/Desktop/dev/do"] {
      XCTAssertEqual(
        SearchRanking.rank(paths.map { item($0) }, query: query, events: []).map(\.id), [paths[0]])
    }
  }

  func testTrailingSlashOnlyMatchesFoldersAndTreatsMetacharactersLiterally() {
    let folder = item("/Users/test/dev/a*b")
    let file = item("/Users/test/dev/a*b.txt", kind: .file)
    XCTAssertEqual(
      SearchRanking.rank([file, folder], query: "dev/a*b/", events: []).map(\.id), [folder.id])
    XCTAssertTrue(
      SearchRanking.rank([item("/Users/test/dev/axxb")], query: "dev/a*b", events: []).isEmpty)
  }

  func testPathSearchPreservesOrdinaryFilenameSearchAndRejectsTraversal() {
    let docs = item("/Users/test/dev/docs")
    XCTAssertEqual(SearchRanking.rank([docs], query: "docs", events: []), [docs])
    for query in ["dev/../docs", "dev//docs", "https://example.com/docs"] {
      XCTAssertTrue(SearchRanking.rank([docs], query: query, events: []).isEmpty)
    }
  }
}
