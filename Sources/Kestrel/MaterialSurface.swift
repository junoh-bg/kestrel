import AppKit

/// One material treatment for every palette; text and controls remain opaque.
@MainActor final class KestrelMaterialSurface: NSView {
  let effect = NSVisualEffectView()
  private let tint = NSView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    autoresizingMask = [.width, .height]
    effect.material = .hudWindow
    effect.blendingMode = .behindWindow
    effect.state = .active
    for view in [effect, tint] {
      view.frame = bounds
      view.autoresizingMask = [.width, .height]
      addSubview(view)
    }
    tint.wantsLayer = true
    updateTheme()
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(accessibilityChanged),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func updateTheme(reduceTransparency: Bool? = nil) {
    let opaque =
      reduceTransparency ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    effect.isHidden = opaque
    tint.layer?.backgroundColor =
      KestrelBrand.background.withAlphaComponent(
        opaque ? 1 : (KestrelBrand.theme.isDark ? 0.70 : 0.80)
      ).cgColor
  }

  @objc private func accessibilityChanged() { updateTheme() }
}
