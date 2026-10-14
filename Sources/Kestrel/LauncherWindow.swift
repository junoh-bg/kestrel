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
  override func cancelOperation(_ sender: Any?) { onDismiss?() }
  override func close() { onDismiss?() }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    let commandW = modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "w"
    if event.keyCode == 53 || commandW {
      onDismiss?()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
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
  private var currentQuery = ""
  private var selectedKey: String?
  private var reloading = false
  var searchAccessMessage = "Search access unverified · Open Settings to check" {
    didSet { searchNotice.stringValue = searchAccessMessage }
  }
  init(model: AppModel, catalog: AppCatalog) {
    self.model = model
    self.catalog = catalog
    panel = KeyPanel(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    super.init()
    panel.onDismiss = { [weak self] in self?.dismiss() }
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
    let heading = NSTextField(labelWithString: "Kestrel")
    heading.font = .systemFont(ofSize: 16, weight: .semibold)
    heading.textColor = KestrelBrand.text
    let mark = NSImageView()
    mark.image = KestrelBrand.mark(size: 28)
    mark.translatesAutoresizingMaskIntoConstraints = false
    mark.widthAnchor.constraint(equalToConstant: 28).isActive = true
    mark.heightAnchor.constraint(equalToConstant: 28).isActive = true
    input.placeholderAttributedString = NSAttributedString(
      string: "Search apps, files, or Google",
      attributes: [
        .font: NSFont.systemFont(ofSize: 25, weight: .medium), .foregroundColor: KestrelBrand.muted,
      ])
    input.font = .systemFont(ofSize: 25, weight: .medium)
    input.isBordered = false
    input.focusRingType = .none
    input.drawsBackground = false
    input.textColor = KestrelBrand.text
    input.delegate = self
    input.maximumNumberOfLines = 1
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 57
    table.intercellSpacing = NSSize(width: 0, height: 4)
    table.backgroundColor = .clear
    table.delegate = self
    table.dataSource = self
    table.target = self
    table.doubleAction = #selector(performSelected)
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    footer.font = .systemFont(ofSize: 11)
    footer.textColor = KestrelBrand.muted
    let settings = KestrelInlineButton(
      title: "Settings", target: self, action: #selector(openSettings))
    settings.bezelStyle = .inline
    settings.updateTheme()
    let bottom = NSStackView(views: [footer, NSView(), settings])
    bottom.orientation = .horizontal
    let divider = NSBox()
    divider.boxType = .separator
    let close = KestrelInlineButton(title: "Close ×", target: self, action: #selector(dismiss))
    close.bezelStyle = .inline
    close.updateTheme()
    close.toolTip = "Hide Kestrel (Escape or Command–W)"
    let header = NSStackView(views: [mark, heading, NSView(), close])
    header.orientation = .horizontal
    searchNotice.font = .systemFont(ofSize: 11)
    searchNotice.textColor = KestrelBrand.muted
    let stack = NSStackView(views: [header, input, divider, scroll, searchNotice, bottom])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    content.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
      header.widthAnchor.constraint(equalTo: stack.widthAnchor),
      divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
      input.widthAnchor.constraint(equalTo: stack.widthAnchor),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
      scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
      bottom.widthAnchor.constraint(equalTo: stack.widthAnchor),
      searchNotice.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }
  func show() {
    if let screen = NSScreen.main {
      let frame = screen.visibleFrame
      panel.setFrameOrigin(
        NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2 + 80))
    }
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(input)
    input.selectText(nil)
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
      ?? "⌥Space · ↑↓ select · Return open · Esc / ⌘W close"
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
    if query.isEmpty {
      rows = apps.prefix(7).map {
        LauncherRow(title: $0.title, subtitle: $0.subtitle, symbol: "app", action: .open($0))
      }
      rows.append(
        LauncherRow(
          title: "Clipboard history", subtitle: "Type clip · searchable local history",
          symbol: "doc.on.clipboard", action: .copy("")))
      rows.append(
        LauncherRow(
          title: "Saved snippets", subtitle: "Type snip · reusable text", symbol: "text.badge.plus",
          action: .copy("")))
    }
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
    let appIDs = Set(apps.map(\.id))
    var seen = Set<String>()
    let candidates = (folders + indexed).filter {
      (!fileOnly || $0.kind != .application) && !appIDs.contains($0.id)
        && seen.insert($0.id).inserted
    }
    let ordered = candidates.sorted {
      if $0.url.pathComponents.count != $1.url.pathComponents.count {
        return $0.url.pathComponents.count < $1.url.pathComponents.count
      }
      return $0.url.path < $1.url.path
    }
    let ranked = SearchRanking.rank(ordered, query: term, events: model.state.usage)
    let exactFolders = ranked.filter {
      $0.kind == .folder && $0.title.caseInsensitiveCompare(term) == .orderedSame
    }
    let promotedFolders = Array(exactFolders.prefix(3))
    let exactIDs = Set(promotedFolders.map(\.id))
    var result = promotedFolders.map(launcherRow)
    result += apps.map(launcherRow)
    if !fileOnly, !term.isEmpty, "Kestrel Settings".localizedCaseInsensitiveContains(term) {
      result.append(
        LauncherRow(
          title: "Kestrel Settings", subtitle: "Clipboard history and snippets",
          symbol: "gearshape", action: .settings))
    }
    result += ranked.filter { !exactIDs.contains($0.id) }.prefix(12).map(launcherRow)
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
    defer { reloading = false }
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
    guard !reloading, rows.indices.contains(table.selectedRow) else { return }
    selectedKey = key(rows[table.selectedRow])
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
    title.font = .systemFont(ofSize: 15, weight: .medium)
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
    let row = rows[table.selectedRow]
    switch row.action {
    case .open(let candidate):
      guard NSWorkspace.shared.open(candidate.url) else {
        footer.stringValue = "Could not open \(candidate.title)"
        return
      }
      model.record(
        candidate,
        query: currentQuery.hasPrefix("file ") ? String(currentQuery.dropFirst(5)) : currentQuery)
    case .copy(let text):
      if text.isEmpty {
        if row.title == "Clipboard history" {
          input.stringValue = "clip"
          updateSearch()
          return
        }
        if row.title == "Saved snippets" {
          input.stringValue = "snip"
          updateSearch()
          return
        }
        return
      }
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
    files.cancel()
    debounce?.cancel()
    panel.orderOut(nil)
  }
  @objc func dismiss() {
    files.cancel()
    debounce?.cancel()
    panel.orderOut(nil)
  }
  @objc private func openSettings() {
    dismiss()
    showSettings?()
  }
}
