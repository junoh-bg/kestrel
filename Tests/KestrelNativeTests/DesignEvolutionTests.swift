import AppKit
import KestrelCore
import Testing

@testable import Kestrel

@MainActor private func descendant<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
  (view as? T).map { [$0] } ?? view.subviews.flatMap { descendant(of: type, in: $0) }
}

@Test @MainActor func emptyLauncherIsCompactAndSearchKeepsItsTopEdge() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let catalog = AppCatalog()
  catalog.refresh()
  let launcher = LauncherWindow(
    model: try AppModel(directory: directory, pasteboard: .withUniqueName()), catalog: catalog)
  defer { launcher.dismiss() }
  launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  let compact = launcher.panel.frame
  #expect(compact.height <= 180)
  launcher.input.stringValue = "settings"
  launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  #expect(launcher.panel.frame.height > compact.height)
  #expect(abs(launcher.panel.frame.maxY - compact.maxY) < 1)
  #expect(launcher.panel.frame.height <= 600)
  launcher.input.stringValue = ""
  launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  #expect(abs(launcher.panel.frame.height - compact.height) < 1)
}

@Test @MainActor func localResultActionsCopyTheSelectedPathWithoutChangingTheQuery() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let pasteboard = NSPasteboard.withUniqueName()
  let launcher = LauncherWindow(
    model: try AppModel(directory: directory, pasteboard: pasteboard), catalog: AppCatalog())
  defer { launcher.dismiss() }
  launcher.input.stringValue = "Downloads"
  launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  let content = try #require(launcher.panel.contentView)
  let actions = try #require(
    descendant(of: NSButton.self, in: content).first { $0.title == "Actions ⌘K" })
  let menu = try #require(actions.menu)
  #expect(menu.items.contains { $0.title == "Show in Finder" })
  let copy = try #require(menu.items.first { $0.title == "Copy Path" })
  let target = try #require(copy.target as? NSObject)
  let selector = try #require(copy.action)
  target.perform(selector, with: copy)
  #expect(
    pasteboard.string(forType: .string)
      == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path)
  #expect(launcher.input.stringValue == "Downloads")
}

@Test @MainActor func copyResultsExposeCopyActionsInsteadOfFileActions() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let pasteboard = NSPasteboard.withUniqueName()
  let launcher = LauncherWindow(
    model: try AppModel(directory: directory, pasteboard: pasteboard), catalog: AppCatalog())
  defer { launcher.dismiss() }
  launcher.input.stringValue = "= 12 * 8"
  launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  let content = try #require(launcher.panel.contentView)
  let actions = try #require(
    descendant(of: NSButton.self, in: content).first { $0.title == "Actions ⌘K" })
  let menu = try #require(actions.menu)
  #expect(!menu.items.contains { ["Show in Finder", "Copy Path"].contains($0.title) })
  let copy = try #require(menu.items.first { $0.title == "Copy Result" })
  let target = try #require(copy.target as? NSObject)
  let selector = try #require(copy.action)
  target.perform(selector, with: copy)
  #expect(pasteboard.string(forType: .string) == "96")
}

@Test @MainActor func launcherAndSettingsShareMaterialAcrossThemeChanges() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {
    try? FileManager.default.removeItem(at: directory)
    KestrelBrand.setTheme(.nightflight)
  }
  let model = try AppModel(directory: directory, pasteboard: .withUniqueName())
  let launcher = LauncherWindow(model: model, catalog: AppCatalog())
  let settings = SettingsWindow(model: model)
  for theme in KestrelTheme.allCases {
    KestrelBrand.setTheme(theme)
    for window in [launcher.panel, settings.window] {
      let content = try #require(window.contentView)
      let material = try #require(descendant(of: NSVisualEffectView.self, in: content).first)
      #expect(material.blendingMode == .behindWindow)
      // A conventional title bar sits outside the content material and needs its own background.
      if !window.styleMask.contains(.fullSizeContentView) {
        #expect(!window.titlebarAppearsTransparent)
      }
      #expect(window.appearance?.name == (theme.isDark ? .darkAqua : .aqua))
    }
  }
}

@Test @MainActor func actionMenuKeepsItsOriginalTargetAfterQueryChanges() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let board = NSPasteboard.withUniqueName()
  let launcher = LauncherWindow(
    model: try AppModel(directory: directory, pasteboard: board), catalog: AppCatalog())
  defer { launcher.dismiss() }
  launcher.input.stringValue = "Downloads"
  launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  let button = try #require(
    descendant(of: NSButton.self, in: launcher.panel.contentView!).first {
      $0.title == "Actions ⌘K"
    })
  let copy = try #require(button.menu?.items.first { $0.title == "Copy Path" })
  launcher.table.deselectAll(nil)
  #expect(button.menu == nil)
  launcher.input.stringValue = "= 2 + 2"
  launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  let target = try #require(copy.target as? NSObject)
  let selector = try #require(copy.action)
  target.perform(selector, with: copy)
  #expect(
    board.string(forType: .string)
      == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path)
  launcher.input.stringValue = ""
  launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  #expect(launcher.table.numberOfRows == 0)
  #expect(button.isHidden)
  #expect(button.menu == nil)
}

@Test @MainActor func materialHasOpaqueAccessibilityFallbackAndCanRestoreGlass() {
  defer { KestrelBrand.setTheme(.nightflight) }
  let surface = KestrelMaterialSurface(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
  for theme in KestrelTheme.allCases {
    KestrelBrand.setTheme(theme)
    surface.updateTheme(reduceTransparency: true)
    #expect(surface.effect.isHidden)
    let tint = surface.subviews.last?.layer?.backgroundColor
    #expect(tint?.alpha == 1)
    #expect(tint == KestrelBrand.background.cgColor)
    surface.updateTheme(reduceTransparency: false)
    #expect(!surface.effect.isHidden)
    #expect((surface.subviews.last?.layer?.backgroundColor?.alpha ?? 1) < 1)
  }
}

@Test @MainActor func commandKRoutesToActionsWithoutDismissingLauncher() throws {
  let panel = KeyPanel(
    contentRect: NSRect(x: 0, y: 0, width: 660, height: 126), styleMask: [.titled],
    backing: .buffered, defer: false)
  var actions = 0
  var dismissals = 0
  panel.onActions = { actions += 1 }
  panel.onDismiss = { dismissals += 1 }
  let event = try #require(
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
      windowNumber: panel.windowNumber, context: nil, characters: "k",
      charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40))
  #expect(panel.performKeyEquivalent(with: event))
  #expect(actions == 1)
  #expect(dismissals == 0)
}

@Test @MainActor func selectedFolderIconRetainsPaletteContrastInLightThemes() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {
    try? FileManager.default.removeItem(at: directory)
    KestrelBrand.setTheme(.nightflight)
  }
  let launcher = LauncherWindow(
    model: try AppModel(directory: directory, pasteboard: .withUniqueName()), catalog: AppCatalog())
  defer { launcher.dismiss() }
  for theme in [KestrelTheme.paper, .arctic] {
    KestrelBrand.setTheme(theme)
    launcher.input.stringValue = "Downloads"
    launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    launcher.panel.orderFront(nil)
    launcher.panel.contentView?.layoutSubtreeIfNeeded()
    let row = try #require(launcher.table.view(atColumn: 0, row: 0, makeIfNecessary: true))
    let icon = try #require(descendant(of: NSImageView.self, in: row).first)
    let bitmap = try #require(icon.bitmapImageRepForCachingDisplay(in: icon.bounds))
    launcher.panel.effectiveAppearance.performAsCurrentDrawingAppearance {
      icon.cacheDisplay(in: icon.bounds, to: bitmap)
    }
    var coloredPixels = 0
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
          color.alphaComponent > 0.2,
          (color.redComponent + color.greenComponent + color.blueComponent) / 3 < 0.65
        {
          coloredPixels += 1
        }
      }
    }
    #expect(coloredPixels > 5, "Selected folder icon needs visible palette color in \(theme.title)")
  }
}

@Test @MainActor func launcherShortcutsWorkWithKoreanInputSource() throws {
  let panel = KeyPanel(
    contentRect: NSRect(x: 0, y: 0, width: 660, height: 126), styleMask: [.titled],
    backing: .buffered, defer: false)
  var actions = 0
  var dismissals = 0
  panel.onActions = { actions += 1 }
  panel.onDismiss = { dismissals += 1 }
  for (character, keyCode) in [("ㅏ", UInt16(40)), ("ㅈ", UInt16(13))] {
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: character,
        charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode))
    #expect(panel.performKeyEquivalent(with: event))
  }
  #expect(actions == 1)
  #expect(dismissals == 1)
}
