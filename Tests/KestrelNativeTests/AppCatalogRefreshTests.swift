import AppKit
import Testing

@testable import Kestrel

@Suite(.serialized) @MainActor struct AppCatalogRefreshTests {
  private func fixture() throws -> (URL, AppCatalog, LauncherWindow) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let catalog = AppCatalog(roots: [root.path])
    catalog.refresh()
    let model = try AppModel(
      directory: root.appendingPathComponent("data"), pasteboard: .withUniqueName())
    return (root, catalog, LauncherWindow(model: model, catalog: catalog))
  }

  private func pumpRunLoop() {
    RunLoop.current.run(until: Date().addingTimeInterval(0.025))
  }

  private func waitUntil(_ predicate: () -> Bool, seconds: Double = 3) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate() && Date() < deadline {
      pumpRunLoop()
      try await Task.sleep(for: .milliseconds(25))
    }
    #expect(predicate())
  }

  @Test func reopeningLauncherDiscoversInstalledAppsAndUpdatesVisibleResults() async throws {
    let (root, catalog, launcher) = try fixture()
    defer {
      launcher.dismiss()
      try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Gemini.app"), withIntermediateDirectories: true)
    launcher.input.stringValue = "Gemini"
    launcher.show()
    try await waitUntil { catalog.candidates.contains { $0.title == "Gemini" } }
    let row = launcher.tableView(launcher.table, viewFor: nil, row: 0)
    let labels = row?.subviews.flatMap { $0.subviews }.compactMap { $0 as? NSTextField } ?? []
    #expect(labels.contains { $0.stringValue == "Gemini" })
  }

  @Test func visibleLauncherDiscoversAppsWithoutReopening() async throws {
    let (root, catalog, launcher) = try fixture()
    defer {
      launcher.dismiss()
      try? FileManager.default.removeItem(at: root)
    }
    launcher.input.stringValue = "Gemini"
    launcher.show()
    #expect(launcher.panel.isVisible)
    // Let the opening refresh finish before installing the fixture.
    try await Task.sleep(for: .milliseconds(150))
    let nested = root.appendingPathComponent("Tools/Gemini.app")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try await waitUntil({ catalog.candidates.contains { $0.title == "Gemini" } }, seconds: 7)
    #expect(
      catalog.candidates.contains {
        $0.url.resolvingSymlinksInPath().path == nested.resolvingSymlinksInPath().path
      })
  }

  @Test func reopeningLauncherDropsRemovedOrRenamedApps() async throws {
    let (root, catalog, launcher) = try fixture()
    defer {
      launcher.dismiss()
      try? FileManager.default.removeItem(at: root)
    }
    let old = root.appendingPathComponent("Before.app")
    let renamed = root.appendingPathComponent("After.app")
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    catalog.refresh()
    #expect(catalog.candidates.contains { $0.title == "Before" })
    try FileManager.default.moveItem(at: old, to: renamed)
    launcher.show()
    try await waitUntil { catalog.candidates.contains { $0.title == "After" } }
    #expect(!catalog.candidates.contains { $0.title == "Before" })
    launcher.dismiss()
    try FileManager.default.removeItem(at: renamed)
    launcher.show()
    try await waitUntil { catalog.candidates.isEmpty }
  }
}
