import AppKit
import KestrelCore

struct LauncherRow {
  enum Action {
    case open(LaunchCandidate)
    case copy(String)
    case google(URL)
    case settings
  }
  let title: String
  let subtitle: String
  let symbol: String
  let action: Action
}

final class KeyPanel: NSPanel {
  var onDismiss: (() -> Void)?
  var onActions: (() -> Void)?
  override func cancelOperation(_ sender: Any?) { onDismiss?() }
  override func close() { onDismiss?() }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    let character = event.charactersIgnoringModifiers?.lowercased()
    let nonLatinInput = character?.unicodeScalars.contains { !$0.isASCII } == true
    // Input methods can report Hangul here even while Command is held.
    // Keep character-based shortcuts for Latin layouts; use their physical key for IMEs.
    let commandW =
      modifiers == .command && (character == "w" || (nonLatinInput && event.keyCode == 13))
    if event.keyCode == 53 || commandW {
      onDismiss?()
      return true
    }
    if modifiers == .command && (character == "k" || (nonLatinInput && event.keyCode == 40)),
      let onActions
    {
      onActions()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor private final class LauncherMenuAction: NSObject {
  let invoke: () -> Void
  init(_ invoke: @escaping () -> Void) { self.invoke = invoke }
}

@MainActor
final class LauncherWindow: NSObject, NSTextFieldDelegate, NSTableViewDataSource,
  NSTableViewDelegate
{
  let panel: KeyPanel
  let input = NSTextField()
  let table = NSTableView()
  let footer = NSTextField(labelWithString: "⌥Space · ↑↓ select · Return open · Esc / ⌘W close")
  let searchNotice = NSTextField(
    wrappingLabelWithString: "Search access unverified · Open Settings to check")
  let catalog: AppCatalog
  let files = FileSearch()
  let model: AppModel
  var showSettings: (() -> Void)?
  private var rows: [LauncherRow] = []
  private var searchVersion = 0
  private var debounce: DispatchWorkItem?
  private var catalogRefreshTimer: Timer?
  private var currentQuery = ""
  private var selectedKey: String?
  private var reloading = false
  private let resultsScroll = NSScrollView()
  private let emptyLabel = NSTextField(
    labelWithString: "No indexed matches. Try a shorter name or check Search in Settings.")
  private var resultsHeight: NSLayoutConstraint!
  private let primaryButton = KestrelInlineButton(title: "Open ↵", target: nil, action: nil)
  private let actionsButton = KestrelInlineButton(title: "Actions ⌘K", target: nil, action: nil)
  var searchAccessMessage = "Search access unverified · Open Settings to check" {
    didSet {
      searchNotice.stringValue = searchAccessMessage
      resultsScroll.toolTip = searchAccessMessage
    }
  }
  init(model: AppModel, catalog: AppCatalog) {
    self.model = model
    self.catalog = catalog
    panel = KeyPanel(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 126),
      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    super.init()
    catalog.changed = { [weak self] in self?.refresh() }
    panel.onDismiss = { [weak self] in self?.dismiss() }
    panel.onActions = { [weak self] in self?.showActions() }
    panel.title = "Kestrel"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    panel.hidesOnDeactivate = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    KestrelBrand.apply(to: panel)
    buildUI()
  }
  private func buildUI() {
    guard let content = panel.contentView else { return }
    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    let mark = NSImageView()
    mark.image = KestrelBrand.mark(size: 28)
    mark.translatesAutoresizingMaskIntoConstraints = false
    mark.widthAnchor.constraint(equalToConstant: 28).isActive = true
    mark.heightAnchor.constraint(equalToConstant: 28).isActive = true
    input.placeholderAttributedString = NSAttributedString(
      string: "Search apps, files, or Google",
      attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .regular),
        .foregroundColor: KestrelBrand.muted,
      ])
    input.font = .systemFont(ofSize: 22, weight: .regular)
    input.isBordered = false
    input.focusRingType = .none
    input.drawsBackground = false
    input.textColor = KestrelBrand.text
    input.delegate = self
    input.maximumNumberOfLines = 1
    input.setAccessibilityLabel("Search Kestrel")
    input.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let close = KestrelInlineButton(title: "Close ×", target: self, action: #selector(dismiss))
    close.toolTip = "Hide Kestrel (Escape or Command–W)"
    let header = NSStackView(views: [mark, input, close])
    header.orientation = .horizontal
    header.spacing = 12
    header.heightAnchor.constraint(equalToConstant: 64).isActive = true

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 52
    table.intercellSpacing = NSSize(width: 0, height: 4)
    table.backgroundColor = .clear
    table.delegate = self
    table.dataSource = self
    table.target = self
    table.doubleAction = #selector(performSelected)
    resultsScroll.documentView = table
    resultsScroll.hasVerticalScroller = true
    resultsScroll.autohidesScrollers = true
    resultsScroll.drawsBackground = false
    resultsScroll.toolTip = searchAccessMessage
    emptyLabel.font = .systemFont(ofSize: 12)
    emptyLabel.textColor = KestrelBrand.muted
    emptyLabel.lineBreakMode = .byTruncatingTail
    emptyLabel.alignment = .center
    resultsScroll.addSubview(emptyLabel)
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      emptyLabel.leadingAnchor.constraint(equalTo: resultsScroll.leadingAnchor, constant: 8),
      emptyLabel.trailingAnchor.constraint(equalTo: resultsScroll.trailingAnchor, constant: -8),
      emptyLabel.centerYAnchor.constraint(equalTo: resultsScroll.centerYAnchor),
    ])
    resultsHeight = resultsScroll.heightAnchor.constraint(equalToConstant: 0)
    resultsHeight.isActive = true

    footer.font = .systemFont(ofSize: 11)
    footer.textColor = KestrelBrand.muted
    footer.lineBreakMode = .byTruncatingTail
    footer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let settings = KestrelInlineButton(
      title: "Settings", target: self, action: #selector(openSettings))
    primaryButton.target = self
    primaryButton.action = #selector(performSelected)
    actionsButton.target = self
    actionsButton.action = #selector(showActions)
    actionsButton.toolTip = "Actions for the selected result (Command–K)"
    for button in [settings, primaryButton, actionsButton, close] {
      button.bezelStyle = .inline
      button.updateTheme()
      button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    let bottom = NSStackView(views: [settings, footer, NSView(), primaryButton, actionsButton])
    bottom.orientation = .horizontal
    bottom.spacing = 14
    bottom.heightAnchor.constraint(equalToConstant: 38).isActive = true
    let divider = NSBox()
    divider.boxType = .separator
    let stack = NSStackView(views: [header, resultsScroll, divider, bottom])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    content.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -7),
      header.widthAnchor.constraint(equalTo: stack.widthAnchor),
      divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
      resultsScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
      bottom.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
    updatePresentation()
  }

  private func updatePresentation() {
    let resultHeight: CGFloat = currentQuery.isEmpty ? 0 : CGFloat(max(1, min(rows.count, 7))) * 56
    resultsHeight.constant = resultHeight
    emptyLabel.isHidden = !rows.isEmpty || currentQuery.isEmpty
    emptyLabel.setAccessibilityHidden(emptyLabel.isHidden)
    var frame = panel.frame
    let height: CGFloat = 126 + resultHeight
    frame.origin.y = frame.maxY - height
    frame.size.height = height
    panel.setFrame(frame, display: true)
    updateActions()
  }

  private func primaryTitle(for row: LauncherRow) -> String? {
    switch row.action {
    case .open(let candidate):
      switch candidate.kind {
      case .application: return "Open Application"
      case .folder: return "Open Folder"
      case .file: return "Open File"
      }
    case .copy(let text): return text.isEmpty ? nil : "Copy Result"
    case .google: return "Search Google"
    case .settings: return "Open Settings"
    }
  }

  private func updateActions() {
    guard rows.indices.contains(table.selectedRow),
      let title = primaryTitle(for: rows[table.selectedRow])
    else {
      primaryButton.isHidden = true
      actionsButton.isHidden = true
      actionsButton.menu = nil
      return
    }
    let row = rows[table.selectedRow]
    let query = currentQuery
    primaryButton.title = title + " ↵"
    primaryButton.updateTheme()
    primaryButton.isHidden = false
    actionsButton.isHidden = false
    let menu = NSMenu(title: "Actions")
    menu.autoenablesItems = false
    func add(_ title: String, _ invoke: @escaping () -> Void) {
      let item = NSMenuItem(
        title: title, action: #selector(invokeMenuAction(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = LauncherMenuAction(invoke)
      menu.addItem(item)
    }
    // Snapshot the result and query: delayed search results must not retarget an open menu.
    add(title) { [weak self] in self?.perform(row, query: query) }
    if case .open(let candidate) = row.action {
      menu.addItem(.separator())
      add("Show in Finder") { [weak self] in
        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
        self?.dismiss()
      }
      add("Copy Path") { [weak self] in
        self?.model.copy(candidate.url.path)
        self?.footer.stringValue = "Path copied"
      }
    }
    actionsButton.menu = menu
  }

  @objc private func invokeMenuAction(_ sender: NSMenuItem) {
    (sender.representedObject as? LauncherMenuAction)?.invoke()
  }

  @objc private func showActions() {
    guard !actionsButton.isHidden, let menu = actionsButton.menu else { return }
    menu.popUp(
      positioning: nil, at: NSPoint(x: 0, y: actionsButton.bounds.maxY + 6), in: actionsButton)
  }
  func show() {
    if let screen = NSScreen.main {
      let frame = screen.visibleFrame
      // Leave room below the idle panel for its maximum result height.
      let top = min(frame.maxY - 16, max(frame.midY + 143, frame.minY + 534))
      panel.setFrameOrigin(
        NSPoint(x: frame.midX - panel.frame.width / 2, y: top - panel.frame.height))
    }
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(input)
    input.selectText(nil)
    catalog.refreshInBackground()
    catalogRefreshTimer?.invalidate()
    catalogRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) {
      [weak self] timer in
      MainActor.assumeIsolated {
        guard let self, self.panel.isVisible else {
          timer.invalidate()
          return
        }
        self.catalog.refreshInBackground()
      }
    }
    updateSearch()
  }
  func refresh() { if panel.isVisible { updateSearch() } }
  func controlTextDidChange(_ obj: Notification) { updateSearch() }
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch NSStringFromSelector(selector) {
    case "insertNewline:":
      performSelected()
      return true
    case "moveDown:":
      select(delta: 1)
      return true
    case "moveUp:":
      select(delta: -1)
      return true
    case "cancelOperation:":
      dismiss()
      return true
    default: return false
    }
  }
  private func select(delta: Int) {
    guard !rows.isEmpty else { return }
    let index = max(0, min(rows.count - 1, table.selectedRow + delta))
    table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    table.scrollRowToVisible(index)
  }
  private func updateSearch() {
    searchVersion += 1
    let version = searchVersion
    debounce?.cancel()
    files.cancel()
    let newQuery = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if newQuery != currentQuery { selectedKey = nil }
    currentQuery = newQuery
    let query = currentQuery
    footer.stringValue =
      model.errorMessage ?? model.startupWarning
      ?? (query.isEmpty ? "Type clip for history · snip for snippets" : "↑↓ select · Esc close")
    if query == "clip" || query.hasPrefix("clip ") {
      let filter = String(query.dropFirst(4)).trimmingCharacters(in: .whitespaces)
      rows = model.state.history.filter {
        Date().timeIntervalSince($0.date) <= 30 * 86400
          && (filter.isEmpty || $0.text.localizedCaseInsensitiveContains(filter))
      }.prefix(30).map {
        LauncherRow(
          title: preview($0.text),
          subtitle:
            "Clipboard · \($0.date.formatted(date: .abbreviated, time: .shortened)) · Return to copy",
          symbol: "doc.on.clipboard", action: .copy($0.text))
      }
      footer.stringValue =
        model.captureEnabled
        ? "Clipboard history is enabled · Return copies without pasting"
        : "Clipboard history is paused · Enable it in Settings"
      if rows.isEmpty {
        rows = [
          LauncherRow(
            title: "No clipboard items",
            subtitle: "Enable capture in Settings, then copy some text", symbol: "pause.circle",
            action: .settings)
        ]
      }
      reload()
      return
    }
    if query == "snip" || query.hasPrefix("snip ") {
      let filter = String(query.dropFirst(4)).trimmingCharacters(in: .whitespaces)
      rows = model.state.snippets.filter {
        filter.isEmpty
          || ($0.title + " " + $0.keyword + " " + $0.text).localizedCaseInsensitiveContains(filter)
      }.prefix(30).map {
        LauncherRow(
          title: $0.title, subtitle: "\($0.keyword) · \(preview($0.text))",
          symbol: "text.badge.plus", action: .copy($0.text))
      }
      if rows.isEmpty {
        rows = [
          LauncherRow(
            title: "Create your first snippet", subtitle: "Save reusable text in Settings",
            symbol: "plus.circle", action: .settings)
        ]
      }
      reload()
      return
    }
    if query.caseInsensitiveCompare("kestrel settings") == .orderedSame {
      rows = [
        LauncherRow(
          title: "Kestrel Settings", subtitle: "Clipboard history and snippets",
          symbol: "gearshape", action: .settings)
      ]
      reload()
      return
    }
    let expression = query.hasPrefix("=") ? String(query.dropFirst()) : query
    let arithmetic =
      query.hasPrefix("=")
      || (query.first.map { $0.isNumber || $0 == "(" || $0 == "-" } == true
        && query.contains { "+-*/^()".contains($0) })
    if arithmetic, let value = Calculator.evaluate(expression) {
      let answer = String(format: "%.12g", value)
      rows = [
        LauncherRow(
          title: answer,
          subtitle: "\(expression.trimmingCharacters(in: .whitespaces)) · Return to copy",
          symbol: "equal.circle", action: .copy(answer))
      ]
      reload()
      return
    }
    if query.hasPrefix("=") {
      rows = [
        LauncherRow(
          title: "Enter a valid calculation", subtitle: "Use numbers, + − * / ^ and parentheses",
          symbol: "equal.circle", action: .copy(""))
      ]
      reload()
      return
    }
    let fileOnly = query.hasPrefix("file ")
    let term = fileOnly ? String(query.dropFirst(5)) : query
    let apps =
      fileOnly
      ? []
      : Array(
        SearchRanking.rank(catalog.candidates, query: term, events: model.state.usage).prefix(10))
    let folders = FolderCatalog.candidates(additionalScopes: files.additionalScopes)
    rows = browsingRows(apps: apps, folders: folders, indexed: [], term: term, fileOnly: fileOnly)
    if query.isEmpty { rows = [] }
    reload()
    guard term.count >= 2 else { return }
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.searchVersion == version else { return }
        self.files.search(term) { [weak self] found in
          guard let self, self.searchVersion == version else { return }
          self.rows = self.browsingRows(
            apps: apps, folders: folders, indexed: found, term: term, fileOnly: fileOnly)
          self.reload()
        }
      }
    }
    debounce = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
  }
  func browsingRows(
    apps: [LaunchCandidate], folders: [LaunchCandidate], indexed: [LaunchCandidate], term: String,
    fileOnly: Bool
  ) -> [LauncherRow] {
    let orderedLocations = (folders + indexed).sorted {
      if $0.url.pathComponents.count != $1.url.pathComponents.count {
        return $0.url.pathComponents.count < $1.url.pathComponents.count
      }
      return $0.url.path < $1.url.path
    }
    var seen = Set<String>()
    let candidates = (apps + orderedLocations).filter {
      (!fileOnly || $0.kind != .application) && seen.insert($0.id).inserted
    }
    let ranked = SearchRanking.rank(candidates, query: term, events: model.state.usage)
    // Type priority is stronger than relevance and applies before the visible limits.
    // Keep relevance and learned ordering within each type, regardless of arrival time.
    let applications = ranked.filter { $0.kind == .application }
    let locations = ranked.filter { $0.kind == .folder } + ranked.filter { $0.kind == .file }
    var result = Array(applications.prefix(10)).map(launcherRow)
    result += locations.prefix(12).map(launcherRow)
    if !fileOnly, !term.isEmpty, "Kestrel Settings".localizedCaseInsensitiveContains(term) {
      result.append(
        LauncherRow(
          title: "Kestrel Settings", subtitle: "Clipboard history and snippets",
          symbol: "gearshape", action: .settings))
    }
    if !fileOnly, !term.isEmpty, let url = GoogleSearch.url(for: term) {
      result.append(
        LauncherRow(
          title: "Search Google for “\(term)”", subtitle: "Opens in your default browser",
          symbol: "magnifyingglass", action: .google(url)))
    }
    return result
  }

  private func launcherRow(_ candidate: LaunchCandidate) -> LauncherRow {
    let symbol: String
    switch candidate.kind {
    case .application: symbol = "app"
    case .folder: symbol = "folder"
    case .file: symbol = "doc"
    }
    return LauncherRow(
      title: candidate.title, subtitle: candidate.subtitle, symbol: symbol, action: .open(candidate)
    )
  }

  private func key(_ row: LauncherRow) -> String {
    switch row.action {
    case .open(let c): return "open:" + c.url.path
    case .google(let u): return "google:" + u.absoluteString
    case .copy(let text): return "copy:" + (text.isEmpty ? row.title : text)
    case .settings: return "settings"
    }
  }
  private func reload() {
    reloading = true
    defer {
      reloading = false
      updatePresentation()
    }
    table.reloadData()
    if !rows.isEmpty {
      let previousIndex = rows.firstIndex { key($0) == selectedKey }
      if previousIndex == nil { selectedKey = nil }
      let index = previousIndex ?? 0
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      // Preserve only a deliberate selection, never the provisional first row.
    }
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !reloading else { return }
    selectedKey = rows.indices.contains(table.selectedRow) ? key(rows[table.selectedRow]) : nil
    updateActions()
  }
  private func preview(_ text: String) -> String {
    String(text.replacingOccurrences(of: "\n", with: " ↵ ").prefix(100))
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    KestrelResultRow()
  }
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard rows.indices.contains(row) else { return nil }
    let result = rows[row]
    let icon = NSImageView()
    icon.image = NSImage(systemSymbolName: result.symbol, accessibilityDescription: result.symbol)
    icon.contentTintColor = KestrelBrand.accent
    if case .open(let candidate) = result.action, candidate.kind == .application {
      icon.image = NSWorkspace.shared.icon(forFile: candidate.url.path)
    }
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
    let title = NSTextField(labelWithString: result.title)
    title.font = .systemFont(ofSize: 14, weight: .medium)
    title.lineBreakMode = .byTruncatingTail
    title.textColor = KestrelBrand.text
    let subtitle = NSTextField(labelWithString: result.subtitle)
    subtitle.font = .systemFont(ofSize: 11)
    subtitle.textColor = KestrelBrand.muted
    subtitle.lineBreakMode = .byTruncatingMiddle
    let labels = NSStackView(views: [title, subtitle])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 4
    let cell = NSStackView(views: [icon, labels])
    cell.orientation = .horizontal
    cell.spacing = 12
    cell.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
    return cell
  }
  @objc func performSelected() {
    guard rows.indices.contains(table.selectedRow) else { return }
    perform(rows[table.selectedRow], query: currentQuery)
  }

  private func perform(_ row: LauncherRow, query: String) {
    switch row.action {
    case .open(let candidate):
      guard NSWorkspace.shared.open(candidate.url) else {
        footer.stringValue = "Could not open \(candidate.title)"
        return
      }
      model.record(
        candidate,
        query: query.hasPrefix("file ") ? String(query.dropFirst(5)) : query)
    case .copy(let text):
      guard !text.isEmpty else { return }
      model.copy(text)
    case .google(let url):
      guard NSWorkspace.shared.open(url) else {
        footer.stringValue = "Could not open your browser"
        return
      }
    case .settings:
      openSettings()
      return
    }
    dismiss()
  }
  @objc func dismiss() {
    catalogRefreshTimer?.invalidate()
    catalogRefreshTimer = nil
    files.cancel()
    debounce?.cancel()
    panel.orderOut(nil)
  }
  @objc private func openSettings() {
    dismiss()
    showSettings?()
  }
}
