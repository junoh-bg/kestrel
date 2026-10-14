import AppKit
import Foundation

@main struct MakeIcon {
  @MainActor static func main() throws {
    let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
      for scale in [1, 2] {
        let count = size * scale
        let pixels = CGFloat(count)
        guard
          let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: count, pixelsHigh: count,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
          throw NSError(
            domain: "Kestrel", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Cannot create icon bitmap"])
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        KestrelBrand.background.setFill()
        NSBezierPath(
          roundedRect: NSRect(
            x: pixels * 0.04, y: pixels * 0.04,
            width: pixels * 0.92, height: pixels * 0.92), xRadius: pixels * 0.20,
          yRadius: pixels * 0.20
        ).fill()
        KestrelBrand.mark(size: pixels * 0.84).draw(
          in: NSRect(
            x: pixels * 0.08,
            y: pixels * 0.08, width: pixels * 0.84, height: pixels * 0.84))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
          throw NSError(
            domain: "Kestrel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot encode icon"])
        }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
      }
    }
  }
}
