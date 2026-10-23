import AppKit

// Vector-drawn build asset; all sizes are rendered directly, without resampling.
let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let variants: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
    ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)
]

func polygon(_ points: [NSPoint], fill: NSColor) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close()
    fill.setFill()
    path.fill()
    NSColor(white: 1, alpha: 0.16).setStroke()
    path.lineWidth = 1.5
    path.stroke()
}

for (name, pixels) in variants {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
        fatalError("Could not create icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 210, yRadius: 210)
    NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.10, alpha: 1).setFill()
    background.fill()
    NSColor(white: 1, alpha: 0.10).setStroke()
    background.lineWidth = 3
    background.stroke()
    polygon([NSPoint(x: 512, y: 820), NSPoint(x: 806, y: 650), NSPoint(x: 512, y: 480), NSPoint(x: 218, y: 650)],
            fill: NSColor(calibratedRed: 0.37, green: 0.40, blue: 0.44, alpha: 1))
    polygon([NSPoint(x: 218, y: 650), NSPoint(x: 512, y: 480), NSPoint(x: 512, y: 174), NSPoint(x: 218, y: 344)],
            fill: NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.28, alpha: 1))
    polygon([NSPoint(x: 512, y: 480), NSPoint(x: 806, y: 650), NSPoint(x: 806, y: 344), NSPoint(x: 512, y: 174)],
            fill: NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.18, alpha: 1))
    for row in 0..<2 {
        for column in 0..<2 {
            let x = CGFloat(578 + column * 105)
            let y = CGFloat(344 + row * 105 + column * 61)
            polygon([NSPoint(x: x, y: y + 58), NSPoint(x: x + 56, y: y + 90),
                     NSPoint(x: x + 56, y: y + 32), NSPoint(x: x, y: y)],
                    fill: NSColor(calibratedRed: 0.56, green: 0.77, blue: 0.74, alpha: row == 1 && column == 0 ? 1 : 0.24))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fatalError("Could not draw app icon")
    }
    try data.write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
