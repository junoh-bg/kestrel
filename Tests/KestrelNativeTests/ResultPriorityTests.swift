import AppKit
import KestrelCore
import Testing

@testable import Kestrel

@MainActor private func priorityCandidate(
  _ id: String, _ title: String, _ kind: LaunchCandidate.Kind
) -> LaunchCandidate {
  LaunchCandidate(
    id: id, title: title, subtitle: id, kind: kind,
    url: URL(fileURLWithPath: "/test/" + id))
}

private func openIDs(_ rows: [LauncherRow]) -> [String] {
  rows.compactMap {
    if case .open(let item) = $0.action { return item.id }
    return nil
  }
}

@Suite(.serialized) @MainActor struct ResultPriorityTests {
  private func fixture() throws -> (URL, AppModel, LauncherWindow) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = try AppModel(directory: root, pasteboard: .withUniqueName())
    return (root, model, LauncherWindow(model: model, catalog: AppCatalog()))
  }

  @Test func arrivingExactFolderCannotDisplaceMatchingApplication() throws {
    let (root, _, launcher) = try fixture()
    defer {
      launcher.dismiss()
      try? FileManager.default.removeItem(at: root)
    }
    let app = priorityCandidate("app", "Gemini", .application)
    let folder = priorityCandidate("folder", "Gemini", .folder)
    let file = priorityCandidate("file", "Gemini.txt", .file)
    let before = launcher.browsingRows(
      apps: [app], folders: [], indexed: [], term: "Gemini", fileOnly: false)
    let after = launcher.browsingRows(
      apps: [app], folders: [], indexed: [file, folder], term: "Gemini", fileOnly: false)
    #expect(openIDs(before) == ["app"])
    #expect(openIDs(after) == ["app", "folder", "file"])
  }

  @Test func indexedAppsAndFuzzyFoldersPrecedeExactFiles() throws {
    let (root, _, launcher) = try fixture()
    defer {
      launcher.dismiss()
      try? FileManager.default.removeItem(at: root)
    }
    let app = priorityCandidate("indexed-app", "Match Editor", .application)
    let folder = priorityCandidate("folder", "My Match Folder", .folder)
    let file = priorityCandidate("file", "Match", .file)
    for input in [[file, folder, app], [app, file, folder], [folder, app, file]] {
      let rows = launcher.browsingRows(
        apps: [], folders: [], indexed: input, term: "Match", fileOnly: false)
      #expect(openIDs(rows) == ["indexed-app", "folder", "file"])
    }
  }

  @Test func localMatchesPrecedeSettingsAndGoogleAndAppsAreDeduplicated() throws {
    let (root, _, launcher) = try fixture()
    defer {
      launcher.dismiss()
      try? FileManager.default.removeItem(at: root)
    }
    let app = priorityCandidate("app", "System Settings", .application)
    let folder = priorityCandidate("folder", "Settings Backup", .folder)
    let file = priorityCandidate("file", "Settings.txt", .file)
    let rows = launcher.browsingRows(
      apps: [app], folders: [folder], indexed: [file, app, folder], term: "settings",
      fileOnly: false)
    #expect(openIDs(rows) == ["app", "folder", "file"])
    #expect(rows.count == 5)
    if case .settings = rows[3].action {
    } else {
      Issue.record("Settings must follow local matches")
    }
    if case .google = rows[4].action {} else { Issue.record("Google must come last") }
  }

  @Test func relevanceAndUsageStillRankWithinEachType() throws {
    let (root, model, launcher) = try fixture()
    defer {
      launcher.dismiss()
      try? FileManager.default.removeItem(at: root)
    }
    let exact = priorityCandidate("exact", "Match", .folder)
    let first = priorityCandidate("first", "Match Alpha", .folder)
    let learned = priorityCandidate("learned", "Match Beta", .folder)
    model.record(learned, query: "Match")
    let rows = launcher.browsingRows(
      apps: [], folders: [first, learned, exact], indexed: [], term: "Match", fileOnly: true)
    #expect(openIDs(rows) == ["exact", "learned", "first"])
  }

  @Test func priorityAppliesBeforeTheVisibleResultLimit() throws {
    let (root, _, launcher) = try fixture()
    defer {
      launcher.dismiss()
      try? FileManager.default.removeItem(at: root)
    }
    let folder = priorityCandidate("folder", "Match Archive", .folder)
    let files = (0..<20).map { priorityCandidate("file-\($0)", "Match", .file) }
    let rows = launcher.browsingRows(
      apps: [], folders: [], indexed: files + [folder], term: "Match", fileOnly: true)
    #expect(openIDs(rows).first == "folder")
    #expect(rows.count == 12)
  }

  @Test func fileModeExcludesAllAppsAndPrioritizesFoldersBeforeFiles() throws {
    let (root, _, launcher) = try fixture()
    defer {
      launcher.dismiss()
      try? FileManager.default.removeItem(at: root)
    }
    let app = priorityCandidate("app", "Match", .application)
    let folder = priorityCandidate("folder", "Match Folder", .folder)
    let file = priorityCandidate("file", "Match", .file)
    let rows = launcher.browsingRows(
      apps: [app], folders: [], indexed: [file, app, folder], term: "Match", fileOnly: true)
    #expect(openIDs(rows) == ["folder", "file"])
    #expect(rows.count == 2)
  }
}
