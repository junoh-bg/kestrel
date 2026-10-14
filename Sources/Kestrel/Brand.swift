import AppKit

enum KestrelTheme: String, CaseIterable {
  case nightflight, evergreen, ember, paper, arctic
  var title: String { rawValue.capitalized }
  var detail: String {
    switch self {
    case .nightflight: return "Deep navy with periwinkle and lavender."
    case .evergreen: return "Forest green with sage and soft gold."
    case .ember: return "Warm burgundy with peach and amber."
    case .paper: return "Light parchment with warm brown."
    case .arctic: return "Cool white and ice blue with ink accents."
    }
  }
  var isDark: Bool { ![.paper, .arctic].contains(self) }
  var colors: [Int] {
    switch self {
    case .nightflight: return [0x111A2B, 0x1C2840, 0x9FB9FF, 0xC8B4EF, 0xE6ECFC, 0xA7B3D4]
    case .evergreen: return [0x10251E, 0x19372C, 0x9AD9A8, 0xE4CA87, 0xE9F3E9, 0xAAC5B3]
    case .ember: return [0x281B22, 0x3C2932, 0xFFA77D, 0xF2C879, 0xF8EBE6, 0xCFB5BE]
    case .paper: return [0xF6F1E7, 0xFFFBF4, 0x825327, 0x744537, 0x2B2925, 0x625D52]
    case .arctic: return [0xEDF4FA, 0xFFFFFF, 0x245B93, 0x5E4497, 0x172C43, 0x52677C]
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
    window.backgroundColor = background
    window.contentView?.wantsLayer = true
    window.contentView?.layer?.backgroundColor = background.cgColor
  }
}

@MainActor final class KestrelResultRow: NSTableRowView {
  override var isEmphasized: Bool {
    get { true }
    set {}
  }
  override func drawSelection(in dirtyRect: NSRect) {
    guard selectionHighlightStyle != .none else { return }
    let rect = bounds.insetBy(dx: 2, dy: 1)
    KestrelBrand.surface.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
    KestrelBrand.highlight.withAlphaComponent(0.75).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
    border.lineWidth = 1
    border.stroke()
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
