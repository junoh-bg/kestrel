import AppKit
import KestrelCore
import Testing

@testable import Kestrel

@Test @MainActor func checkboxLabelsRenderWithContrastAcrossThemesAndStates() throws {
  _ = NSApplication.shared
  defer { KestrelBrand.setTheme(.nightflight) }
  for theme in KestrelTheme.allCases {
    KestrelBrand.setTheme(theme)
    let button = KestrelCheckbox(checkboxWithTitle: "Check automatically", target: nil, action: nil)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 260, height: 80),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    window.contentView!.wantsLayer = true
    window.contentView!.layer?.backgroundColor = KestrelBrand.surface.cgColor
    button.frame = NSRect(x: 20, y: 20, width: 220, height: 32)
    window.contentView!.addSubview(button)
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    button.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    button.updateTheme()
    for state in [NSControl.StateValue.off, .on] {
      button.state = state
      for enabled in [true, false] {
        button.isEnabled = enabled
        for systemAppearance in [NSAppearance.Name.aqua, .darkAqua] {
          window.contentView!.layoutSubtreeIfNeeded()
          RunLoop.current.run(until: Date().addingTimeInterval(0.02))
          let bitmap = try #require(button.bitmapImageRepForCachingDisplay(in: button.bounds))
          NSAppearance(named: systemAppearance)!.performAsCurrentDrawingAppearance {
            button.cacheDisplay(in: button.bounds, to: bitmap)
          }
          var visibleInk = 0
          for y in 0..<bitmap.pixelsHigh {
            // Ignore the native checkbox glyph; inspect only the label.
            for x in (bitmap.pixelsWide / 5)..<bitmap.pixelsWide {
              if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                color.alphaComponent > 0.2
              {
                let brightness =
                  (color.redComponent + color.greenComponent + color.blueComponent) / 3
                if theme.isDark ? brightness > 0.7 : brightness < 0.35 { visibleInk += 1 }
              }
            }
          }
          #expect(
            visibleInk > 80,
            "\(theme.title), state \(state.rawValue), enabled \(enabled), system \(systemAppearance.rawValue): label has \(visibleInk) legible pixels"
          )
        }
      }
    }
  }
}
