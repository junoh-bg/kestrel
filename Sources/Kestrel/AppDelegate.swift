import AppKit
import KestrelCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
  private var statusItem: NSStatusItem?
  private var model: AppModel?
  private var launcher: LauncherWindow?
  private var settings: SettingsWindow?
  private var softwareUpdates: SoftwareUpdates?
  private var hotKey: HotKey?
  private var folderAccess: SearchFolderAccess?
  private let catalog = AppCatalog()
  private var checkingAccess = false
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    do {
      let smoke = ProcessInfo.processInfo.arguments.contains("--smoke-test")
      let directory =
        smoke
        ? URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(
          "kestrel-smoke-" + UUID().uuidString, isDirectory: true)
        : ProcessInfo.processInfo.environment["LOCALPILOT_DATA_DIR"].map {
          URL(fileURLWithPath: $0, isDirectory: true)
        }
          ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("LocalPilot", isDirectory: true)
      let model = try AppModel(directory: directory)
      self.model = model
      KestrelBrand.setTheme(model.theme)
      catalog.refresh()
      let access = SearchFolderAccess(directory: model.store.directory)
      folderAccess = access
      if let error = access.error { model.startupWarning = error }
      let launcher = LauncherWindow(model: model, catalog: catalog)
      self.launcher = launcher
      launcher.files.additionalScopes = access.urls
      let settings = SettingsWindow(model: model)
      self.settings = settings
      launcher.showSettings = { [weak self] in self?.settings?.show() }
      settings.chooseSearchFolder = { [weak self] in self?.chooseSearchFolder() }
      settings.openFullDiskAccess = { [weak settings] in
        guard
          let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        else { return }
        if !NSWorkspace.shared.open(url) {
          settings?.searchAccessStatus.stringValue =
            "Open System Settings → Privacy & Security → Full Disk Access, then add Kestrel."
        }
      }
      settings.checkSearchAccess = { [weak self] in self?.checkSearchAccess() }
      settings.openQuery = { [weak self] query in self?.show(query: query) }
      model.changed = { [weak self] in
        self?.settings?.refresh()
        self?.launcher?.refresh()
      }
      if !smoke && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil {
        let updates = SoftwareUpdates()
        softwareUpdates = updates
        updates.changed = { [weak settings, weak updates] in
          guard let updates else { return }
          settings?.configureUpdates(
            available: updates.canCheckForUpdates,
            automaticallyChecks: updates.automaticallyChecksForUpdates)
        }
        settings.checkForUpdates = { [weak self] in self?.checkForUpdates() }
        settings.automaticUpdateChecksChanged = { [weak updates] enabled in
          updates?.automaticallyChecksForUpdates = enabled
        }
        updates.start()
      }
      setupMenu()
      let hotKey = HotKey { [weak self] in self?.showLauncher() }
      self.hotKey = hotKey
      if !hotKey.register() {
        model.startupWarning = [
          model.startupWarning, "⌥Space is already in use. Open Kestrel from its menu bar icon.",
        ].compactMap { $0 }.joined(separator: " · ")
      }
      model.startMonitoring()
      if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
        runSmokeTest(model: model)
        return
      }
      launcher.show()
    } catch {
      let alert = NSAlert()
      alert.messageText = "Kestrel could not start"
      alert.informativeText = error.localizedDescription
      alert.runModal()
      NSApp.terminate(nil)
    }
  }
  private func setupMenu() {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = status
    status.button?.image = KestrelBrand.mark(size: 20, template: true)
    status.button?.imagePosition = .imageOnly
    status.button?.toolTip = "Kestrel · ⌥Space"
    let menu = NSMenu()
    for (title, action) in [
      ("Open Kestrel", #selector(showLauncher)), ("Clipboard history", #selector(showClipboard)),
      ("Saved snippets", #selector(showSnippets)), ("Settings…", #selector(showSettings)),
      ("Check for Updates…", #selector(checkForUpdates)),
      ("Refresh applications", #selector(refreshApps)), ("Quit Kestrel", #selector(quit)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    status.menu = menu
    let main = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    let updateItem = NSMenuItem(
      title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    updateItem.target = self
    appMenu.addItem(updateItem)
    appMenu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit Kestrel", action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    appMenu.addItem(quit)
    appItem.submenu = appMenu
    main.addItem(appItem)
    let fileItem = NSMenuItem()
    fileItem.title = "File"
    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(
      NSMenuItem(
        title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    fileItem.submenu = fileMenu
    main.addItem(fileItem)
    let editItem = NSMenuItem()
    editItem.title = "Edit"
    let editMenu = NSMenu(title: "Edit")
    for (title, selector, key) in [
      ("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
      ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"),
    ] {
      editMenu.addItem(
        NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
    }
    editItem.submenu = editMenu
    main.addItem(editItem)
    NSApp.mainMenu = main
  }
  private func show(query: String) {
    launcher?.input.stringValue = query
    launcher?.show()
  }
  @objc private func showLauncher() {
    if launcher?.panel.isVisible == true { launcher?.dismiss() } else { show(query: "") }
  }
  @objc private func showClipboard() { show(query: "clip") }
  @objc private func showSnippets() { show(query: "snip") }
  @objc private func showSettings() { settings?.show() }
  private func chooseSearchFolder() {
    guard let settings else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.message =
      "Add access to this folder and its subfolders. Kestrel also searches accessible indexed names in your home folder. For broad access, use Full Disk Access in Settings."
    panel.prompt = "Allow folder"
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    panel.beginSheetModal(for: settings.window) { [weak self] response in
      guard response == .OK, let self, let url = panel.url else { return }
      do {
        try self.folderAccess?.add(url)
        self.launcher?.files.additionalScopes = self.folderAccess?.urls ?? []
        settings.status.stringValue = "Search access added for \(url.lastPathComponent)"
        self.checkSearchAccess()
        self.launcher?.refresh()
      } catch {
        settings.status.stringValue = "Could not save folder access: \(error.localizedDescription)"
        settings.status.textColor = .systemRed
      }
    }
  }
  private func checkSearchAccess() {
    guard !checkingAccess else { return }
    checkingAccess = true
    settings?.searchAccessStatus.stringValue =
      "Checking folder access… macOS may ask for permission."
    let manager = FileManager.default
    let urls =
      [FileManager.SearchPathDirectory.desktopDirectory, .documentDirectory, .downloadsDirectory]
      .flatMap {
        manager.urls(for: $0, in: .userDomainMask)
      } + (folderAccess?.urls ?? [])
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let report = SearchAccessReport.inspect(urls)
      DispatchQueue.main.async {
        guard let self else { return }
        self.checkingAccess = false
        self.settings?.searchAccessStatus.stringValue = report.detail + "\n" + report.summary
        self.launcher?.searchAccessMessage =
          report.entries.contains { $0.state != .readable }
          ? "Some folders unavailable · Check access in Settings"
          : "Folder listing checked · Spotlight exclusions still apply"
        self.launcher?.refresh()
      }
    }
  }
  @objc private func checkForUpdates() {
    launcher?.dismiss()
    softwareUpdates?.checkForUpdates()
  }
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    menuItem.action == #selector(checkForUpdates)
      ? softwareUpdates?.canCheckForUpdates == true : true
  }
  @objc private func refreshApps() {
    catalog.refresh()
    launcher?.refresh()
  }
  @objc private func quit() { NSApp.terminate(nil) }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    settings?.permitLeavingDraft() == false ? .terminateCancel : .terminateNow
  }
  func applicationWillTerminate(_ notification: Notification) {
    hotKey?.unregister()
    model?.stopMonitoring()
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    show(query: "")
    return true
  }
  private func runSmokeTest(model: AppModel) {
    // Explicit developer verification mode requires isolated state; it never reads user data.
    let sample = Snippet(
      title: "Verification snippet", keyword: "check", text: "Kestrel verification")
    let saved = model.saveSnippet(sample)
    let loaded = try? model.store.load()
    let url = GoogleSearch.url(for: "Swift & macOS 한글")
    let report: [String: Any] = [
      "apps_found": catalog.candidates.count, "calculator": Calculator.evaluate("(2+3)*4") == 20,
      "google_encoding": url != nil
        && URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
          == "Swift & macOS 한글",
      "snippet_roundtrip": saved && loaded?.snippets.contains(sample) == true,
      "clipboard_paused": !model.state.captureEnabled, "panel_created": launcher != nil,
      "settings_created": settings != nil,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    {
      print(text)
    }
    let success =
      (report["apps_found"] as? Int ?? 0) > 0
      && report.filter { $0.key != "apps_found" }.values.allSatisfy { ($0 as? Bool) == true }
    hotKey?.unregister()
    model.stopMonitoring()
    try? FileManager.default.removeItem(at: model.store.directory)
    fflush(stdout)
    exit(success ? 0 : 1)
  }
}
