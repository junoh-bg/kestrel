import AppKit
import KestrelCore

@MainActor final class AppCatalog {
  private(set) var candidates: [LaunchCandidate] = []
  func refresh() {
    let roots = [
      "/Applications", "/System/Applications", "/System/Library/CoreServices/Applications",
      NSHomeDirectory() + "/Applications",
    ]
    var found = [String: LaunchCandidate]()
    for root in roots {
      guard
        let enumerator = FileManager.default.enumerator(
          at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles])
      else { continue }
      while let url = enumerator.nextObject() as? URL {
        let depth = url.path.dropFirst(root.count).split(separator: "/").count
        if url.pathExtension == "app" {
          enumerator.skipDescendants()
          guard !["LocalPilot.app", "Kestrel.app"].contains(url.lastPathComponent) else { continue }
          let title = url.deletingPathExtension().lastPathComponent
          found[url.path] = LaunchCandidate(
            id: url.path, title: title, subtitle: "Application", kind: .application, url: url)
        } else if depth >= 3 {
          enumerator.skipDescendants()
        }
      }
    }
    candidates = found.values.sorted {
      $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
  }
}

@MainActor final class FileSearch {
  var additionalScopes: [URL] = []
  private let metadata = MetadataSearch()

  func cancel() { metadata.cancel() }

  func search(_ text: String, completion: @escaping ([LaunchCandidate]) -> Void) {
    cancel()
    guard text.count >= 2 else {
      completion([])
      return
    }
    let scopes: [Any] = [NSMetadataQueryUserHomeScope] + additionalScopes.map { $0 as Any }
    guard let path = PathSearchQuery(text) else {
      metadata.search(text, scopes: scopes, completion: completion)
      return
    }
    if let parent = path.explicitParent {
      searchLeaf(path, text: text, scopes: [parent], completion: completion)
    } else if let parentName = path.parentName {
      // Resolve exact parent directories before searching their children. Never truncate
      // a global list of common leaf names and only then apply the parent path.
      metadata.search(
        parentName, scopes: scopes, comparisons: ["==[cd]"], foldersOnly: true,
        accepts: path.matchesParent
      ) { [weak self] parents in
        guard let self else { return }
        var urls = parents.map(\.url)
        // A selected scope itself may not be included in Spotlight's descendant results.
        urls += self.additionalScopes.filter { path.matchesParent($0) }
        guard !urls.isEmpty else {
          completion([])
          return
        }
        self.searchLeaf(path, text: text, scopes: urls, completion: completion)
      }
    } else {
      searchLeaf(path, text: text, scopes: scopes, completion: completion)
    }
  }

  private func searchLeaf(
    _ path: PathSearchQuery, text: String, scopes: [Any],
    completion: @escaping ([LaunchCandidate]) -> Void
  ) {
    metadata.search(
      path.leaf, scopes: scopes, comparisons: ["==[cd]", "BEGINSWITH[cd]"],
      foldersOnly: path.foldersOnly, rankingQuery: text,
      accepts: { path.matchesParent($0.deletingLastPathComponent()) }, completion: completion)

  }
}

@MainActor private final class MetadataSearch {
  private var queries = [NSMetadataQuery]()
  private var observers = [NSObjectProtocol]()
  private var completed = Set<ObjectIdentifier>()
  private var gathered = [String: LaunchCandidate]()
  private var timeout: DispatchWorkItem?
  private var generation = 0
  private var accepts: (URL) -> Bool = { _ in true }

  func cancel() {
    generation += 1
    timeout?.cancel()
    timeout = nil
    for query in queries { query.stop() }
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    queries = []
    observers = []
    completed = []
    gathered = [:]
  }

  func search(
    _ text: String, scopes: [Any],
    comparisons: [String] = ["==[cd]", "BEGINSWITH[cd]", "CONTAINS[cd]"],
    foldersOnly: Bool = false, rankingQuery: String? = nil,
    accepts: @escaping (URL) -> Bool = { _ in true },
    completion: @escaping ([LaunchCandidate]) -> Void
  ) {
    cancel()
    guard !text.isEmpty else {
      completion([])
      return
    }
    self.accepts = accepts
    let token = generation
    // Bound each tier separately so an exact/prefix match cannot be displaced
    // by alphabetically earlier substring matches before ranking.
    queries = comparisons.map { comparison in
      let query = NSMetadataQuery()
      query.searchScopes = scopes
      let name = NSPredicate(format: "%K " + comparison + " %@", NSMetadataItemFSNameKey, text)
      query.predicate =
        foldersOnly
        ? NSCompoundPredicate(andPredicateWithSubpredicates: [
          name, NSPredicate(format: "%K == %@", NSMetadataItemContentTypeKey, "public.folder"),
        ]) : name
      query.sortDescriptors = [
        NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true),
        NSSortDescriptor(key: NSMetadataItemPathKey, ascending: true),
      ]
      return query
    }
    for query in queries {
      let queryID = ObjectIdentifier(query)
      let observer = NotificationCenter.default.addObserver(
        forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.generation == token,
            let query = self.queries.first(where: { ObjectIdentifier($0) == queryID })
          else { return }
          self.collect(query)
          if self.completed.count == self.queries.count {
            self.deliver(token: token, text: rankingQuery ?? text, completion: completion)
          }
        }
      }
      observers.append(observer)
      if !query.start() { collect(query) }
    }
    if completed.count == queries.count {
      deliver(token: token, text: rankingQuery ?? text, completion: completion)
      return
    }
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        self?.deliver(token: token, text: rankingQuery ?? text, completion: completion)
      }
    }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
  }

  private func collect(_ query: NSMetadataQuery) {
    guard completed.insert(ObjectIdentifier(query)).inserted else { return }
    query.disableUpdates()
    var accepted = 0
    for index in 0..<query.resultCount {
      if accepted >= 160 { break }
      guard let item = query.result(at: index) as? NSMetadataItem,
        let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
      else { continue }
      guard !path.contains("/Library/Application Support/LocalPilot/") else { continue }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      guard accepts(url) else { continue }
      let types = item.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String] ?? []
      let kind: LaunchCandidate.Kind =
        types.contains("com.apple.application-bundle")
        ? .application
        : types.contains("public.folder") ? .folder : .file
      if kind == .application && ["LocalPilot.app", "Kestrel.app"].contains(url.lastPathComponent) {
        continue
      }
      accepted += 1
      let displayPath = FolderCatalog.displayPath(url)
      gathered[url.path] = LaunchCandidate(
        id: url.path,
        title: kind == .application
          ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent,
        subtitle: kind == .folder ? "Folder · " + displayPath : displayPath, kind: kind, url: url)
    }
    query.stop()
  }

  private func deliver(token: Int, text: String, completion: ([LaunchCandidate]) -> Void) {
    guard generation == token, !queries.isEmpty else { return }
    for query in queries { collect(query) }
    let candidates = gathered.values.sorted {
      if $0.url.pathComponents.count != $1.url.pathComponents.count {
        return $0.url.pathComponents.count < $1.url.pathComponents.count
      }
      return $0.url.path < $1.url.path
    }
    let ranked = Array(SearchRanking.rank(candidates, query: text, events: []).prefix(120))
    cancel()
    completion(ranked)
  }
}

@MainActor final class AppModel {
  let store: StateStore
  private(set) var state: StoredState
  private(set) var captureEnabled: Bool
  var errorMessage: String?
  var startupWarning: String?
  var changed: (() -> Void)?
  private var storageBlocked = false
  private var timer: Timer?
  private let pasteboard: NSPasteboard
  private let frontmostApplicationID: () -> String?
  private var lastChange: Int
  private var lastExpiryCheck = Date.distantPast
  private var lastSaveAttempt = Date.distantPast
  private var pendingHistory = [ClipboardItem]()
  init(
    directory: URL, pasteboard: NSPasteboard = .general,
    frontmostApplicationID: @escaping () -> String? = {
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
  ) throws {
    self.pasteboard = pasteboard
    self.frontmostApplicationID = frontmostApplicationID
    store = try StateStore(directory: directory)
    do { state = try store.load() } catch {
      state = StoredState()
      storageBlocked = true
      errorMessage =
        "Saved data could not be read. Your existing file was preserved. \(error.localizedDescription)"
    }
    captureEnabled = state.captureEnabled
    lastChange = pasteboard.changeCount
  }
  func startMonitoring() {
    performMaintenance()
    timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkForClipboardChanges() }
    }
  }
  func stopMonitoring() {
    timer?.invalidate()
    timer = nil
  }
  func checkForClipboardChanges() {
    performMaintenance()
    if !pendingHistory.isEmpty, Date().timeIntervalSince(lastSaveAttempt) >= 2 {
      flushPendingClipboard()
    }
    let board = pasteboard
    guard board.changeCount != lastChange else { return }
    lastChange = board.changeCount
    let types = Set((board.types ?? []).map(\.rawValue))
    let declaredSource = board.string(
      forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
    guard CapturePolicy.allows(types: types, source: declaredSource, enabled: captureEnabled),
      CapturePolicy.allows(
        types: types, source: frontmostApplicationID(),
        enabled: captureEnabled),
      let text = board.string(forType: .string)
    else { return }
    acceptClipboardText(text)
  }
  func performMaintenance(now: Date = Date()) {
    guard now.timeIntervalSince(lastExpiryCheck) >= 60 else { return }
    lastExpiryCheck = now
    var next = state
    next.history = ClipboardHistory.adding("", to: state.history, now: now)
    pendingHistory = ClipboardHistory.adding("", to: pendingHistory, now: now)
    if next.history != state.history { _ = persist(next) }
  }
  func acceptClipboardText(_ text: String, now: Date = Date()) {
    guard captureEnabled else { return }
    pendingHistory = ClipboardHistory.adding(text, to: pendingHistory, now: now)
    flushPendingClipboard()
  }
  func flushPendingClipboard() {
    guard captureEnabled, !pendingHistory.isEmpty else { return }
    lastSaveAttempt = Date()
    var next = state
    next.history = ClipboardHistory.adding("", to: pendingHistory + state.history)
    if persist(next) { pendingHistory = [] }
  }
  @discardableResult func persist(_ requested: StoredState) -> Bool {
    guard !storageBlocked else {
      changed?()
      return false
    }
    do {
      try store.save(requested)
      state = requested
      captureEnabled = requested.captureEnabled
      errorMessage = nil
      changed?()
      return true
    } catch {
      let message = "Could not save changes: \(error.localizedDescription)"
      if errorMessage != message {
        errorMessage = message
        changed?()
      }
      return false
    }
  }
  var theme: KestrelTheme { KestrelTheme(rawValue: state.themeID ?? "") ?? .nightflight }
  @discardableResult func setTheme(_ theme: KestrelTheme) -> Bool {
    var next = state
    next.themeID = theme.rawValue
    return persist(next)
  }
  func setCapture(_ enabled: Bool) {
    var next = state
    next.captureEnabled = enabled
    guard persist(next) else { return }
    lastChange = pasteboard.changeCount
    if !enabled { pendingHistory = [] }
  }
  func clearHistory() {
    pendingHistory = []
    var next = state
    next.history = []
    _ = persist(next)
  }
  func saveSnippet(_ snippet: Snippet) -> Bool {
    var next = state
    if let index = next.snippets.firstIndex(where: { $0.id == snippet.id }) {
      next.snippets[index] = snippet
    } else {
      next.snippets.append(snippet)
    }
    return persist(next)
  }
  func removeSnippet(_ id: UUID) {
    var next = state
    next.snippets.removeAll { $0.id == id }
    _ = persist(next)
  }
  func record(_ candidate: LaunchCandidate, query: String) {
    var next = state
    next.usage.append(UsageEvent(id: candidate.id, query: query, date: Date()))
    next.usage = Array(
      next.usage.filter { Date().timeIntervalSince($0.date) <= 30 * 86400 }.suffix(5000))
    _ = persist(next)
  }
  func copy(_ text: String) {
    let board = pasteboard
    board.clearContents()
    board.setString(text, forType: .string)
    lastChange = board.changeCount
  }
}
