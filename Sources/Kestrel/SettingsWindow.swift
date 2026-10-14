import AppKit
import KestrelCore

private final class SettingsPageView: NSView {
  override var isFlipped: Bool { true }
}

@MainActor
final class SettingsWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
    styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
  let model: AppModel
  let capture = KestrelCheckbox(
    checkboxWithTitle: "Enable clipboard history", target: nil, action: nil)
  let status = NSTextField(wrappingLabelWithString: "")
  let table = NSTableView()
  let titleField = NSTextField()
  let keywordField = NSTextField()
  let bodyField = NSTextView()
  var openQuery: ((String) -> Void)?
  var chooseSearchFolder: (() -> Void)?
  var openFullDiskAccess: (() -> Void)?
  var checkSearchAccess: (() -> Void)?
  let searchAccessStatus = NSTextField(
    wrappingLabelWithString:
      "Search access has not been checked. Missing folders? Use Check access.")
  private enum Section: Int, CaseIterable {
    case general, appearance, search, clipboard, snippets
    var title: String { ["General", "Appearance", "Search", "Clipboard", "Snippets"][rawValue] }
    var symbol: String {
      ["gearshape", "paintpalette", "magnifyingglass", "doc.on.clipboard", "text.badge.plus"][
        rawValue]
    }
  }
  private let pageScroll = NSScrollView()
  private var pages = [Section: NSView]()
  private var navigation = [Section: KestrelNavigationButton]()
  private var selectedSection = Section.general
  private var themeButtons = [KestrelTheme: KestrelActionButton]()
  private var renderedTheme = KestrelBrand.theme
  private var editingID: UUID?
  private var baseline = ["", "", ""]
  private var selecting = false
  var hasUnsavedChanges: Bool {
    [titleField.stringValue, keywordField.stringValue, bodyField.string] != baseline
  }
  init(model: AppModel) {
    self.model = model
    super.init()
    window.delegate = self
    window.titlebarAppearsTransparent = true
    window.title = "Kestrel Settings"
    window.isReleasedWhenClosed = false
    KestrelBrand.apply(to: window)
    buildUI()
    refresh()
  }
  private func buildUI() {
    guard let content = window.contentView else { return }
    window.minSize = NSSize(width: 880, height: 620)
    let sidebar = NSView()
    sidebar.wantsLayer = true
    sidebar.layer?.backgroundColor = KestrelBrand.surface.withAlphaComponent(0.6).cgColor
    let mark = NSImageView()
    mark.image = KestrelBrand.mark(size: 32)
    let brand = NSStackView(views: [mark, label("Kestrel", size: 17, weight: .semibold)])
    brand.orientation = .horizontal
    brand.spacing = 8
    let navigationStack = NSStackView()
    navigationStack.orientation = .vertical
    navigationStack.alignment = .leading
    navigationStack.spacing = 6
    for section in Section.allCases {
      let button = KestrelNavigationButton(
        title: section.title, target: self, action: #selector(changeSection(_:)))
      button.tag = section.rawValue
      button.setButtonType(.toggle)
      button.bezelStyle = .recessed
      button.isBordered = false
      button.wantsLayer = true
      button.layer?.cornerRadius = 7
      button.alignment = .left
      button.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil)
      button.imagePosition = .imageLeading
      button.font = .systemFont(ofSize: 13, weight: .medium)
      button.contentTintColor = KestrelBrand.text
      button.setAccessibilityLabel(section.title)
      button.setAccessibilityHelp("Show " + section.title.lowercased() + " settings")
      navigation[section] = button
      navigationStack.addArrangedSubview(button)
      button.widthAnchor.constraint(equalTo: navigationStack.widthAnchor).isActive = true
      button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }
    let sidebarStack = NSStackView(views: [brand, navigationStack])
    sidebarStack.orientation = .vertical
    sidebarStack.alignment = .leading
    sidebarStack.spacing = 26
    sidebar.addSubview(sidebarStack)
    pageScroll.drawsBackground = false
    pageScroll.hasVerticalScroller = true
    pageScroll.autohidesScrollers = true
    pageScroll.contentView.drawsBackground = false
    status.font = .systemFont(ofSize: 11)
    status.textColor = KestrelBrand.muted
    let divider = NSBox()
    divider.boxType = .separator
    for view in [sidebar, pageScroll, status, divider] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    sidebarStack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      sidebar.topAnchor.constraint(equalTo: content.topAnchor),
      sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      sidebar.widthAnchor.constraint(equalToConstant: 190),
      sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
      sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
      sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 24),
      navigationStack.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor),
      pageScroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
      pageScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      pageScroll.topAnchor.constraint(equalTo: content.topAnchor),
      pageScroll.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -10),
      divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 28),
      divider.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
      divider.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -10),
      status.leadingAnchor.constraint(equalTo: divider.leadingAnchor),
      status.trailingAnchor.constraint(equalTo: divider.trailingAnchor),
      status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
    ])
    buildPages()
    selectSection(.general)
  }

  private func label(
    _ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, muted: Bool = false
  ) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = muted ? KestrelBrand.muted : KestrelBrand.text
    return field
  }

  private func button(_ title: String, _ action: Selector) -> KestrelActionButton {
    let result = KestrelActionButton(title: title, target: self, action: action)
    result.bezelStyle = .rounded
    result.updateTheme()
    return result
  }

  private func row(_ title: String, detail: String, control: NSView) -> NSView {
    let labels = NSStackView(views: [
      label(title, size: 13, weight: .medium), label(detail, muted: true),
    ])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 4
    for item in labels.arrangedSubviews {
      item.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
    }
    control.setContentHuggingPriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(.required, for: .horizontal)
    let content = NSStackView(views: [labels, control])
    content.orientation = .horizontal
    content.distribution = .fill
    content.alignment = .centerY
    content.spacing = 20
    content.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
    return content
  }

  private func group(_ title: String, rows: [NSView]) -> NSView {
    let box = NSStackView()
    box.orientation = .vertical
    box.alignment = .leading
    box.spacing = 0
    box.wantsLayer = true
    box.layer?.backgroundColor = KestrelBrand.surface.cgColor
    box.layer?.cornerRadius = 10
    for (index, row) in rows.enumerated() {
      if index > 0 {
        let divider = NSBox()
        divider.boxType = .separator
        box.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true
      }
      box.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true
    }
    let result = NSStackView(views: [label(title, size: 12, weight: .semibold, muted: true), box])
    result.orientation = .vertical
    result.alignment = .leading
    result.spacing = 8
    box.widthAnchor.constraint(equalTo: result.widthAnchor).isActive = true
    return result
  }

  private func page(_ title: String, subtitle: String, views: [NSView]) -> NSView {
    let header = NSStackView(views: [
      label(title, size: 25, weight: .semibold), label(subtitle, size: 13, muted: true),
    ])
    header.orientation = .vertical
    header.alignment = .leading
    header.spacing = 6
    for item in header.arrangedSubviews {
      item.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
    }
    let stack = NSStackView(views: [header] + views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 24
    let page = SettingsPageView()
    page.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    for item in stack.arrangedSubviews {
      item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 28),
      stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -28),
      stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 28),
      stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -28),
    ])
    return page
  }

  private func buildPages() {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development build"
    pages[.general] = page(
      "General", subtitle: "Your everyday launcher, close at hand.",
      views: [
        group(
          "Keyboard",
          rows: [
            row(
              "Open Kestrel", detail: "Also available from the wing in the menu bar.",
              control: label("⌥ Space", size: 14, weight: .medium)),
            row(
              "Close the launcher", detail: "Kestrel keeps running in the menu bar.",
              control: label("Esc  or  ⌘ W", size: 14, weight: .medium)),
          ]),
        group(
          "Storage",
          rows: [
            row(
              "Stored on this Mac",
              detail: "Clipboard history, snippets, and learned search order.",
              control: button("Show data folder", #selector(showDataFolder)))
          ]),
        group(
          "About",
          rows: [
            row(
              "Kestrel", detail: "Everyday tools, one shortcut away",
              control: label(version, muted: true))
          ]),
      ])
    searchAccessStatus.font = .systemFont(ofSize: 12)
    searchAccessStatus.textColor = KestrelBrand.text
    pages[.search] = page(
      "Search",
      subtitle: "Find applications and indexed files and folders. Web searches use Google.",
      views: [
        group(
          "File access",
          rows: [
            row(
              "Access all protected folders",
              detail:
                "Approve Full Disk Access once in macOS, then quit and reopen Kestrel. This is broad access to protected data.",
              control: button("Full Disk Access…", #selector(openDiskAccess))),
            row(
              "Locate this app", detail: "Use this copy when adding Kestrel in System Settings.",
              control: button("Show Kestrel app", #selector(revealApp))),
            row(
              "Allow a specific folder", detail: "A narrower alternative. Includes its subfolders.",
              control: button("Choose search folder…", #selector(selectSearchFolder))),
          ]),
        group(
          "Diagnostics",
          rows: [
            row(
              "Check folder access",
              detail:
                "Checks Desktop, Documents, Downloads and your selected folders. macOS may ask for permission.",
              control: button("Check access", #selector(checkAccess)))
          ]),
        searchAccessStatus,
        label(
          "Kestrel searches filenames locally using Spotlight. Permission does not make excluded or unindexed files searchable.",
          muted: true),
      ])
    capture.updateTheme()
    capture.target = self
    capture.action = #selector(toggleCapture)
    pages[.clipboard] = page(
      "Clipboard", subtitle: "Find recently copied text by typing clip in Kestrel.",
      views: [
        group(
          "History",
          rows: [
            row(
              "Capture copied text", detail: "Up to 100 text items, kept locally for 30 days.",
              control: capture),
            row(
              "Browse history", detail: "Select an item to copy it, then paste where you need it.",
              control: button("Show history", #selector(showHistory))),
            row(
              "Clear saved history", detail: "Removes clipboard items. Your snippets are kept.",
              control: button("Clear history…", #selector(clearHistory))),
          ]),
        label(
          "Marked concealed, transient, and autogenerated content is skipped. Password-manager detection is best-effort; ordinary copied text may still contain private information.",
          muted: true),
      ])
    pages[.snippets] = makeSnippetsPage()
    let themes = KestrelTheme.allCases.enumerated().map { index, theme -> NSView in
      let choose = button("Use " + theme.title, #selector(chooseTheme(_:)))
      choose.tag = index
      themeButtons[theme] = choose
      let controls = NSStackView(views: [ThemePreview(theme: theme), choose])
      controls.orientation = .horizontal
      controls.spacing = 24
      controls.distribution = .fill
      choose.widthAnchor.constraint(equalToConstant: 80).isActive = true
      controls.widthAnchor.constraint(equalToConstant: 190).isActive = true
      return row(theme.title, detail: theme.detail, control: controls)
    }
    pages[.appearance] = page(
      "Appearance",
      subtitle:
        "Choose a color palette for search and Settings. Changes apply immediately.",
      views: [group("Color theme", rows: themes)])
  }

  private func makeSnippetsPage() -> NSView {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("snippet"))
    table.addTableColumn(column)
    table.backgroundColor = KestrelBrand.surface
    table.headerView = nil
    table.rowHeight = 36
    table.dataSource = self
    table.delegate = self
    table.setAccessibilityLabel("Saved snippets")
    let list = NSScrollView()
    list.documentView = table
    list.hasVerticalScroller = true
    list.heightAnchor.constraint(equalToConstant: 280).isActive = true
    let new = button("New snippet", #selector(newSnippet))
    let delete = button("Delete…", #selector(deleteSnippet))
    let library = NSStackView(views: [
      label("Saved snippets", weight: .semibold), list, new, delete,
    ])
    library.orientation = .vertical
    library.alignment = .leading
    library.spacing = 10
    library.widthAnchor.constraint(equalToConstant: 180).isActive = true
    for item in library.arrangedSubviews {
      item.widthAnchor.constraint(equalTo: library.widthAnchor).isActive = true
    }
    titleField.placeholderAttributedString = NSAttributedString(
      string: "Snippet title", attributes: [.foregroundColor: KestrelBrand.muted])
    keywordField.placeholderAttributedString = NSAttributedString(
      string: "Keyword (optional)", attributes: [.foregroundColor: KestrelBrand.muted])
    titleField.setAccessibilityLabel("Snippet title")
    keywordField.setAccessibilityLabel("Snippet keyword")
    bodyField.setAccessibilityLabel("Snippet text")
    bodyField.backgroundColor = KestrelBrand.surface
    bodyField.textColor = KestrelBrand.text
    bodyField.insertionPointColor = KestrelBrand.accent
    bodyField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    bodyField.isRichText = false
    bodyField.isAutomaticQuoteSubstitutionEnabled = false
    bodyField.isAutomaticDashSubstitutionEnabled = false
    bodyField.isVerticallyResizable = true
    bodyField.autoresizingMask = [.width]
    bodyField.textContainer?.widthTracksTextView = true
    let editorScroll = NSScrollView()
    editorScroll.documentView = bodyField
    editorScroll.hasVerticalScroller = true
    editorScroll.borderType = .bezelBorder
    editorScroll.heightAnchor.constraint(equalToConstant: 230).isActive = true
    let save = KestrelAccentButton(
      title: "Save snippet", target: self, action: #selector(saveSnippet))
    save.bezelStyle = .rounded
    save.updateTheme()
    let actions = NSStackView(views: [NSView(), button("Copy text", #selector(copySnippet)), save])
    actions.orientation = .horizontal
    actions.distribution = .fill
    actions.spacing = 10
    let editor = NSStackView(views: [
      label("Title", weight: .semibold), titleField, label("Keyword", weight: .semibold),
      keywordField, label("Text", weight: .semibold), editorScroll, actions,
    ])
    editor.orientation = .vertical
    editor.alignment = .leading
    editor.spacing = 8
    for item in editor.arrangedSubviews {
      item.widthAnchor.constraint(equalTo: editor.widthAnchor).isActive = true
    }
    let layout = NSStackView(views: [library, editor])
    layout.orientation = .horizontal
    layout.distribution = .fill
    layout.alignment = .top
    layout.spacing = 20
    return page(
      "Snippets",
      subtitle:
        "Reusable text for everyday work. Type snip to find and copy it. Drafts stay here while you browse settings.",
      views: [layout])
  }

  @objc private func changeSection(_ sender: NSButton) {
    guard let section = Section(rawValue: sender.tag) else { return }
    selectSection(section)
  }

  private func selectSection(_ section: Section) {
    guard let page = pages[section] else { return }
    if pageScroll.documentView === page {
      navigation[section]?.state = .on
      return
    }
    // End field editing before detaching the page, preserving the current draft.
    window.makeFirstResponder(nil)
    selectedSection = section
    pageScroll.documentView = page
    page.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      page.leadingAnchor.constraint(equalTo: pageScroll.contentView.leadingAnchor),
      page.topAnchor.constraint(equalTo: pageScroll.contentView.topAnchor),
      page.widthAnchor.constraint(equalTo: pageScroll.contentView.widthAnchor),
    ])
    for (candidate, button) in navigation {
      button.state = candidate == section ? .on : .off
      button.updateTheme()
    }
    pageScroll.contentView.scroll(to: .zero)
    pageScroll.reflectScrolledClipView(pageScroll.contentView)
  }
  func show() {
    refresh()
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
  @objc private func chooseTheme(_ sender: NSButton) {
    guard KestrelTheme.allCases.indices.contains(sender.tag) else { return }
    let choice = KestrelTheme.allCases[sender.tag]
    guard model.setTheme(choice) else {
      refresh()
      return
    }
    KestrelBrand.setTheme(choice)
    for page in pages.values where page.window == nil {
      KestrelBrand.updateDetachedView(page, from: renderedTheme)
    }
    renderedTheme = choice
    refresh()
  }
  func refresh() {
    for (theme, button) in themeButtons {
      button.title = model.theme == theme ? "Selected" : "Use"
      button.updateTheme()
      button.isEnabled = model.theme != theme
      button.setAccessibilityLabel(
        model.theme == theme ? theme.title + ", selected" : "Use " + theme.title)
    }
    let wasSelecting = selecting
    selecting = true
    defer { selecting = wasSelecting }
    capture.state = model.captureEnabled ? .on : .off
    status.stringValue =
      model.errorMessage ?? model.startupWarning
      ?? "\(model.state.history.count) clipboard items · \(model.state.snippets.count) snippets · Data is stored locally"
    if model.errorMessage != nil {
      status.textColor = .systemRed
    } else {
      status.textColor = KestrelBrand.muted
    }
    let selected = editingID
    table.reloadData()
    if let selected, let row = model.state.snippets.firstIndex(where: { $0.id == selected }) {
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
  }
  @objc private func toggleCapture() {
    model.setCapture(capture.state == .on)
    refresh()
  }
  @objc private func showHistory() {
    window.orderOut(nil)
    openQuery?("clip")
  }
  @objc private func openDiskAccess() { openFullDiskAccess?() }
  @objc private func checkAccess() { checkSearchAccess?() }
  @objc private func revealApp() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
  }
  @objc private func selectSearchFolder() { chooseSearchFolder?() }
  @objc private func showDataFolder() { NSWorkspace.shared.open(model.store.directory) }
  @objc private func clearHistory() {
    let alert = NSAlert()
    alert.messageText = "Clear clipboard history?"
    alert.informativeText =
      "This removes saved clipboard items from Kestrel. Your snippets are kept."
    alert.addButton(withTitle: "Clear history")
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { [weak self] response in
      if response == .alertFirstButtonReturn {
        self?.model.clearHistory()
        self?.refresh()
      }
    }
  }
  @objc private func newSnippet() {
    guard permitLeavingDraft() else { return }
    selecting = true
    editingID = nil
    table.deselectAll(nil)
    selecting = false
    titleField.stringValue = ""
    keywordField.stringValue = ""
    bodyField.string = ""
    baseline = ["", "", ""]
    window.makeFirstResponder(titleField)
  }
  @objc private func saveSnippet() { _ = saveCurrentSnippet() }
  @discardableResult private func saveCurrentSnippet() -> Bool {
    let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = bodyField.string
    guard !title.isEmpty, title.count <= 128, keywordField.stringValue.count <= 80,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 100_000
    else {
      status.stringValue =
        "Enter a title and text (up to 100 KB). Titles: 128 characters; keywords: 80."
      status.textColor = .systemRed
      return false
    }
    let snippet = Snippet(
      id: editingID ?? UUID(), title: title,
      keyword: keywordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), text: text)
    if model.saveSnippet(snippet) {
      editingID = snippet.id
      titleField.stringValue = snippet.title
      keywordField.stringValue = snippet.keyword
      baseline = [snippet.title, snippet.keyword, snippet.text]
      refresh()
      status.stringValue = "Snippet saved · type snip in Kestrel to find it"
      return true
    }
    return false
  }
  @objc private func deleteSnippet() {
    guard permitLeavingDraft(), let id = editingID else { return }
    let alert = NSAlert()
    alert.messageText = "Delete this snippet?"
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn, let self else { return }
      self.model.removeSnippet(id)
      if self.model.errorMessage == nil {
        self.baseline = [
          self.titleField.stringValue, self.keywordField.stringValue, self.bodyField.string,
        ]
        self.newSnippet()
      }
      self.refresh()
    }
  }
  @objc private func copySnippet() {
    guard !bodyField.string.isEmpty else { return }
    model.copy(bodyField.string)
    status.stringValue = "Copied · paste wherever you need it"
  }
  func numberOfRows(in tableView: NSTableView) -> Int { model.state.snippets.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard model.state.snippets.indices.contains(row) else { return nil }
    let label = NSTextField(labelWithString: model.state.snippets[row].title)
    label.lineBreakMode = .byTruncatingTail
    label.textColor = KestrelBrand.text
    return label
  }
  func permitLeavingDraft() -> Bool {
    guard hasUnsavedChanges else { return true }
    let alert = NSAlert()
    alert.messageText = "Save your snippet changes?"
    alert.informativeText = "You have unsaved text in the snippet editor."
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Discard")
    alert.addButton(withTitle: "Cancel")
    let response = alert.runModal()
    if response == .alertFirstButtonReturn { return saveCurrentSnippet() }
    if response == .alertSecondButtonReturn {
      titleField.stringValue = baseline[0]
      keywordField.stringValue = baseline[1]
      bodyField.string = baseline[2]
      return true
    }
    return false
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool { permitLeavingDraft() }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !selecting, model.state.snippets.indices.contains(table.selectedRow) else { return }
    selecting = true
    defer { selecting = false }
    let snippet = model.state.snippets[table.selectedRow]
    if snippet.id == editingID { return }
    guard permitLeavingDraft() else {
      selecting = true
      if let editingID, let row = model.state.snippets.firstIndex(where: { $0.id == editingID }) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      } else {
        table.deselectAll(nil)
      }
      selecting = false
      return
    }
    if let intendedRow = model.state.snippets.firstIndex(where: { $0.id == snippet.id }) {
      table.selectRowIndexes(IndexSet(integer: intendedRow), byExtendingSelection: false)
    }
    editingID = snippet.id
    titleField.stringValue = snippet.title
    keywordField.stringValue = snippet.keyword
    bodyField.string = snippet.text
    baseline = [snippet.title, snippet.keyword, snippet.text]
  }
}
