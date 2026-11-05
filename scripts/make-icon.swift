import AppKit

// All platforms and the README derive from the approved, checked-in master.
let arguments = CommandLine.arguments
let synchronize = arguments.count == 3 && arguments[2] == "--sync-assets"
guard arguments.count == 2 || synchronize else {
    fatalError("Usage: swift scripts/make-icon.swift ICONSET [--sync-assets]")
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = root.appendingPathComponent("Resources/AppIcon.png")
guard let image = NSImage(contentsOf: sourceURL), image.size.width > 0,
      image.size.width == image.size.height else {
    fatalError("Resources/AppIcon.png must contain a square image")
}
let iconset = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let variants: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
    ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)
]
func render(_ pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero,
        operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
    return data
}
var images: [Int: Data] = [:]
for (name, pixels) in variants {
    let data: Data
    if let cached = images[pixels] { data = cached }
    else { data = try render(pixels); images[pixels] = data }
    try data.write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
if synchronize {
    // Windows 10/11 accept PNG-backed ICO frames; 256 is encoded as zero in its directory.
    let sizes = [16, 32, 48, 64, 128, 256]
    let frames = try sizes.map { pixels in try images[pixels] ?? render(pixels) }
    func littleEndian(_ value: UInt32, bytes: Int) -> [UInt8] {
        (0..<bytes).map { UInt8((value >> (8 * $0)) & 0xff) }
    }
    var ico = Data([0, 0, 1, 0] + littleEndian(UInt32(sizes.count), bytes: 2))
    var offset = UInt32(6 + sizes.count * 16)
    for (size, frame) in zip(sizes, frames) {
        let dimension = UInt8(size == 256 ? 0 : size)
        ico.append(contentsOf: [dimension, dimension, 0, 0, 1, 0, 32, 0])
        ico.append(contentsOf: littleEndian(UInt32(frame.count), bytes: 4))
        ico.append(contentsOf: littleEndian(offset, bytes: 4))
        offset += UInt32(frame.count)
    }
    for frame in frames { ico.append(frame) }
    try ico.write(to: root.appendingPathComponent("windows/assets/icon.ico"))
    try images[512]!.write(to: root.appendingPathComponent("windows/assets/icon.png"))
    try images[256]!.write(to: root.appendingPathComponent("docs/images/app-icon.png"))
}
