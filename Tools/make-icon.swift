import AppKit

// Draws the app icon into an .iconset directory; build.sh turns it into .icns.
// Usage: make-icon <output.iconset>

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func renderIcon(pixels: Int) -> Data? {
    let side = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.current = context

    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    let inset = side * 0.045
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                            xRadius: side * 0.22,
                            yRadius: side * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.52, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 0.05, green: 0.24, blue: 0.66, alpha: 1.0),
    ])
    gradient?.draw(in: path, angle: -90)

    if let symbol = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: nil) {
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.44, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))
        if let configured = symbol.withSymbolConfiguration(configuration) {
            let size = configured.size
            let origin = NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)
            configured.draw(in: NSRect(origin: origin, size: size))
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

for variant in variants {
    guard let data = renderIcon(pixels: variant.pixels) else {
        FileHandle.standardError.write(Data("cannot render \(variant.name)\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: output).appendingPathComponent(variant.name)
    try? data.write(to: url)
}
print("iconset written to \(output)")
