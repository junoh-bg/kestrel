import AppKit

enum KestrelTheme: String, CaseIterable {
  case nightflight, evergreen, ember, paper, arctic
  // Persisted raw values retain the user's palette family across upgrades.
  var title: String {
    switch self {
    case .nightflight: return "Nightflight"
    case .evergreen: return "Moss"
    case .ember: return "Dusk"
    case .paper: return "Linen"
    case .arctic: return "Frost"
    }
  }
  var detail: String {
    switch self {
    case .nightflight: return "Smoked navy with ice-blue accents."
    case .evergreen: return "Deep forest with quiet sage accents."
    case .ember: return "Smoked plum with soft rose accents."
    case .paper: return "Warm mineral white with umber accents."
    case .arctic: return "Frosted blue-white with slate accents."
    }
  }
  var isDark: Bool { ![.paper, .arctic].contains(self) }
  var colors: [Int] {
    switch self {
    case .nightflight: return [0x101D30, 0x24354B, 0x97D9EE, 0xC3E7F2, 0xF0F5FC, 0xB1C0D3]
    case .evergreen: return [0x16251F, 0x2C3D32, 0xB6D1A5, 0xD8E5CB, 0xF0F4ED, 0xB8C8B9]
    case .ember: return [0x281F32, 0x403348, 0xE0B0C9, 0xEDD2E0, 0xF7F0F8, 0xCBBCCC]
    case .paper: return [0xF3F0E9, 0xE4DFD5, 0x795635, 0x65472D, 0x292825, 0x625C53]
    case .arctic: return [0xEFF5F8, 0xDCE8EE, 0x28657C, 0x214F67, 0x1B3040, 0x4E6675]
    }
  }
}

@MainActor enum KestrelBrand {
  private(set) static var theme = KestrelTheme.nightflight
  private static let windows = NSHashTable<NSWindow>.weakObjects()
  static var background: NSColor { color(theme.colors[0]) }
  static var surface: NSColor { color(theme.colors[1]) }
  static var accent: NSColor { color(theme.colors[2]) }
  static var highlight: NSColor { color(theme.colors[3]) }
  static var text: NSColor { color(theme.colors[4]) }
  static var muted: NSColor { color(theme.colors[5]) }

  static func setTheme(_ next: KestrelTheme) {
    guard next != theme else { return }
    let previous = theme
    theme = next
    for window in windows.allObjects {
      apply(to: window)
      if let content = window.contentView { recolor(content, from: previous, to: next) }
    }
  }

  private static func remap(_ value: NSColor?, from old: KestrelTheme, to new: KestrelTheme)
    -> NSColor?
  {
    guard let value, let rgb = value.usingColorSpace(.sRGB) else { return value }
    for (source, target) in zip(old.colors, new.colors) {
      let candidate = color(source)
      if abs(rgb.redComponent - candidate.redComponent) < 0.001,
        abs(rgb.greenComponent - candidate.greenComponent) < 0.001,
        abs(rgb.blueComponent - candidate.blueComponent) < 0.001
      {
        return color(target).withAlphaComponent(rgb.alphaComponent)
      }
    }
    return value
  }

  private static func recolor(_ view: NSView, from old: KestrelTheme, to new: KestrelTheme) {
    // Theme previews intentionally retain their own palette.
    if view is ThemePreview { return }
    if let material = view as? KestrelMaterialSurface {
      material.updateTheme()
      return
    }
    // Treat AppKit rendering subviews as opaque. Our controls set their own
    // semantic colors explicitly rather than remapping resolved system colors.
    if let button = view as? NSButton {
      (button as? KestrelNavigationButton)?.updateTheme()
      (button as? KestrelInlineButton)?.updateTheme()
      (button as? KestrelAccentButton)?.updateTheme()
      (button as? KestrelActionButton)?.updateTheme()
      button.needsDisplay = true
      return
    }
    if let cg = view.layer?.backgroundColor {
      view.layer?.backgroundColor = remap(NSColor(cgColor: cg), from: old, to: new)?.cgColor
    }
    if let field = view as? NSTextField {
      field.textColor = remap(field.textColor, from: old, to: new)
      field.backgroundColor =
        remap(field.backgroundColor, from: old, to: new) ?? field.backgroundColor
      if let placeholder = field.placeholderAttributedString {
        field.placeholderAttributedString = remap(placeholder, from: old, to: new)
      }
    }
    if let editor = view as? NSTextView {
      editor.textColor = remap(editor.textColor, from: old, to: new)
      editor.backgroundColor =
        remap(editor.backgroundColor, from: old, to: new) ?? editor.backgroundColor
      editor.insertionPointColor =
        remap(editor.insertionPointColor, from: old, to: new) ?? editor.insertionPointColor
    }
    if let table = view as? NSTableView {
      table.backgroundColor =
        remap(table.backgroundColor, from: old, to: new) ?? table.backgroundColor
    }
    if let image = view as? NSImageView {
      image.contentTintColor = remap(image.contentTintColor, from: old, to: new)
      if image.image?.accessibilityDescription == "Kestrel wing", let size = image.image?.size.width
      {
        image.image = mark(size: size)
      }
    }
    for child in view.subviews { recolor(child, from: old, to: new) }
    view.needsDisplay = true
  }

  private static func remap(
    _ text: NSAttributedString, from old: KestrelTheme, to new: KestrelTheme
  ) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: text)
    text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      if let value = value as? NSColor, let color = remap(value, from: old, to: new) {
        result.addAttribute(.foregroundColor, value: color, range: range)
      }
    }
    return result
  }

  // Detached Settings pages are retained for drafts; recolor them too.
  static func updateDetachedView(_ view: NSView, from old: KestrelTheme) {
    recolor(view, from: old, to: theme)
  }
  static func color(_ hex: Int) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
      blue: CGFloat(hex & 255) / 255, alpha: 1)
  }
  // One geometry shared by the app icon, wordmark, and monochrome menu icon.
  static func mark(size: CGFloat, template: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    (template ? NSColor.black : accent).setFill()
    let wing = NSBezierPath()
    for (index, point) in [
      (0.13, 0.28), (0.46, 0.80), (0.90, 0.71), (0.55, 0.53), (0.49, 0.24), (0.38, 0.47),
    ].enumerated() {
      let p = NSPoint(x: point.0 * size, y: point.1 * size)
      if index == 0 { wing.move(to: p) } else { wing.line(to: p) }
    }
    wing.close()
    wing.fill()
    image.unlockFocus()
    image.isTemplate = template
    image.accessibilityDescription = "Kestrel wing"
    return image
  }
  static func apply(to window: NSWindow) {
    windows.add(window)
    let appearance: NSAppearance.Name = theme.isDark ? .darkAqua : .aqua
    if window.appearance?.name != appearance {
      window.appearance = NSAppearance(named: appearance)
    }
    window.isOpaque = false
    window.backgroundColor = .clear
    guard let content = window.contentView else { return }
    content.wantsLayer = true
    content.layer?.backgroundColor = NSColor.clear.cgColor
    content.layer?.cornerRadius = window.styleMask.contains(.fullSizeContentView) ? 18 : 0
    content.layer?.masksToBounds = true
    if let material = content.subviews.compactMap({ $0 as? KestrelMaterialSurface }).first {
      material.updateTheme()
    } else {
      content.addSubview(
        KestrelMaterialSurface(frame: content.bounds), positioned: .below, relativeTo: nil)
    }
  }
}

@MainActor final class KestrelResultRow: NSTableRowView {
  // Our selection background is deliberately subtle, including in light palettes.
  // Do not let AppKit substitute white template icons for a dark system selection.
  override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
  override var isEmphasized: Bool {
    get { true }
    set {}
  }
  override func drawSelection(in dirtyRect: NSRect) {
    guard selectionHighlightStyle != .none else { return }
    let rect = bounds.insetBy(dx: 2, dy: 1)
    KestrelBrand.surface.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
    KestrelBrand.accent.withAlphaComponent(0.20).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
    border.lineWidth = 1
    border.stroke()
    KestrelBrand.accent.setFill()
    NSBezierPath(
      roundedRect: NSRect(x: rect.minX + 1, y: rect.midY - 10, width: 3, height: 20), xRadius: 1.5,
      yRadius: 1.5
    ).fill()
  }
}

@MainActor final class ThemePreview: NSView {
  let theme: KestrelTheme
  init(theme: KestrelTheme) {
    self.theme = theme
    super.init(frame: .zero)
    setAccessibilityElement(true)
    setAccessibilityLabel(theme.title + " color preview")
    widthAnchor.constraint(equalToConstant: 86).isActive = true
    heightAnchor.constraint(equalToConstant: 40).isActive = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func draw(_ dirtyRect: NSRect) {
    let colors = theme.colors.map(KestrelBrand.color)
    colors[0].setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    colors[1].setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 7, dy: 6), xRadius: 3, yRadius: 3).fill()
    for (index, color) in [colors[2], colors[3], colors[4]].enumerated() {
      color.setFill()
      NSBezierPath(
        roundedRect: NSRect(x: 14, y: 11 + index * 8, width: 48 - index * 8, height: 4), xRadius: 2,
        yRadius: 2
      ).fill()
    }
  }
}

@MainActor final class KestrelNavigationButton: NSButton {
  func updateTheme() {
    let selected = state == .on
    let color = selected ? KestrelBrand.highlight : KestrelBrand.text
    contentTintColor = color
    layer?.backgroundColor =
      selected
      ? KestrelBrand.accent.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    let styled = NSAttributedString(
      string: title,
      attributes: [
        .foregroundColor: color, .font: font ?? NSFont.systemFont(ofSize: 13, weight: .medium),
        .paragraphStyle: paragraph,
      ])
    // Toggle buttons can draw either title depending on selection and mouse state.
    attributedTitle = styled
    attributedAlternateTitle = styled
  }
}

@MainActor final class KestrelInlineButton: NSButton {
  func updateTheme() {
    attributedTitle = NSAttributedString(
      string: title, attributes: [.foregroundColor: KestrelBrand.muted])
  }
}

@MainActor final class KestrelAccentButton: NSButton {
  func updateTheme() {
    bezelColor = KestrelBrand.accent
    contentTintColor = KestrelBrand.background
  }
}

@MainActor class KestrelActionButton: NSButton {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    cell = KestrelActionButtonCell(textCell: "")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  var titleColor: NSColor { KestrelBrand.text }
  var usesPaletteBackground: Bool { true }
  func updateTheme() {
    if usesPaletteBackground {
      bezelStyle = .recessed
      isBordered = false
      wantsLayer = true
      layer?.cornerRadius = 5
      layer?.backgroundColor = KestrelBrand.accent.withAlphaComponent(0.12).cgColor
      layer?.borderWidth = 0.5
      layer?.borderColor = KestrelBrand.accent.withAlphaComponent(0.3).cgColor
    }
    contentTintColor = titleColor
    attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .foregroundColor: titleColor,
        .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
      ])
    attributedAlternateTitle = attributedTitle
  }
}

@MainActor final class KestrelCheckbox: KestrelActionButton {
  override var usesPaletteBackground: Bool { false }
}

// A custom cell keeps AppKit's native bezel, keyboard handling and accessibility,
// while drawing labels directly instead of caching a hosted appearance-dependent label.
@MainActor final class KestrelActionButtonCell: NSButtonCell {
  override func drawTitle(
    _ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView
  ) -> NSRect {
    guard let button = controlView as? KestrelActionButton else {
      return super.drawTitle(title, withFrame: frame, in: controlView)
    }
    let styled = NSMutableAttributedString(attributedString: title)
    styled.addAttribute(
      .foregroundColor, value: button.titleColor.withAlphaComponent(isEnabled ? 1 : 0.5),
      range: NSRange(location: 0, length: styled.length))
    return super.drawTitle(styled, withFrame: frame, in: controlView)
  }
}
