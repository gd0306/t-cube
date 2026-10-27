import AppKit
import RealityKit
import CubeCore
import Testing
import ImageIO
import UniformTypeIdentifiers
@testable import TCube

@MainActor
struct SlimeRenderPreviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_SLIME_PREVIEWS"] == "1"))
    func exportNativePointerPullAndRebound() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        var configuration = CubeConfiguration()
        configuration.autoRotatesWhenIdle = false
        for face in CubeFace.allCases {
            for name in ["Messages", "Calendar", "Music", "Notes"] {
                try configuration.add(LauncherItem(url: URL(fileURLWithPath: "/System/Applications/\(name).app"), name: name, kind: .application), to: face)
            }
        }
        try store.save(configuration)
        let view = CubeView(model: AppModel(store: store))
        let surface = CubeSurfaceView(cubeView: view)
        let window = NSPanel(contentRect: NSRect(x: 180, y: 180, width: 440, height: 440), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.contentView = surface
        view.environment.background = .color(NSColor(white: 0.085, alpha: 1))
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/slime-previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let destination = try #require(CGImageDestinationCreateWithURL(output.appendingPathComponent("slime-motion.gif") as CFURL, UTType.gif.identifier as CFString, 60, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<60 {
            if index >= 8 && index < 42 {
                let phase = Float(index - 8) / 33
                let contact = FaceLayout.surfacePoint(at: [0.36 * sin(phase * 2 * .pi), 0.24 * cos(phase * 2 * .pi)])
                let point = try #require(view.project(view.cube.convert(position: contact, to: nil)))
                let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: Double(index) / 15, windowNumber: window.windowNumber, context: nil, eventNumber: index, clickCount: 0, pressure: 0))
                surface.input.mouseMoved(with: event)
            } else { view.setHovered(false) }
            try await Task.sleep(for: .milliseconds(67))
            let snapshot: NSImage? = await withCheckedContinuation { continuation in
                view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
            }
            let rendered = try #require(snapshot?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            CGImageDestinationAddImage(destination, rendered, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.067]] as CFDictionary)
            if [0, 20, 35, 43, 59].contains(index) {
                let bitmap = NSBitmapImageRep(cgImage: rendered)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("slime-\(index).png"))
            }
        }
        #expect(CGImageDestinationFinalize(destination))
        view.setHovered(false)
        view.environment.background = .color(NSColor(white: 0.9, alpha: 1))
        try await Task.sleep(for: .milliseconds(400))
        let light: NSImage? = await withCheckedContinuation { continuation in
            view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        let rendered = try #require(light?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try #require(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("slime-light.png"))
        view.environment.background = .color(.clear)
        try await Task.sleep(for: .milliseconds(300))
        let transparent: NSImage? = await withCheckedContinuation { continuation in
            view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        let clearImage = try #require(transparent?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let clearBitmap = NSBitmapImageRep(cgImage: clearImage)
        let center = try #require(clearBitmap.colorAt(x: clearBitmap.pixelsWide / 2, y: clearBitmap.pixelsHigh / 2))
        #expect(center.alphaComponent > 0.20 && center.alphaComponent < 0.80,
                "The gel must remain visible in the actual clear window without becoming opaque")
        try #require(clearBitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("slime-transparent.png"))
        let context = try #require(CGContext(data: nil, width: clearImage.width, height: clearImage.height,
                                            bitsPerComponent: 8, bytesPerRow: clearImage.width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: clearImage.width, height: clearImage.height))
        context.draw(clearImage, in: CGRect(x: 0, y: 0, width: clearImage.width, height: clearImage.height))
        let composite = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        let onWhite = try #require(composite.colorAt(x: composite.pixelsWide / 2, y: composite.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        #expect(min(onWhite.redComponent, onWhite.greenComponent, onWhite.blueComponent) < 0.97,
                "A real transparent snapshot must retain visible gel tint over white wallpaper")
        try #require(composite.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("slime-white-composite.png"))
    }
}
