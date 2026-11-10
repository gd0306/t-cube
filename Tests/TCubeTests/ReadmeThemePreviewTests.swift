import AppKit
import CubeCore
import ImageIO
import RealityKit
import Testing
import UniformTypeIdentifiers
@testable import TCube

/// Documentation-only studio lighting. Never changes the application's scene or user data.
@MainActor
struct ReadmeThemePreviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_README_THEME_PREVIEWS"] == "1"))
    func exportDarkPagePreviews() async throws {
        _ = NSApplication.shared
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = ConfigurationStore(url: temporary.appendingPathComponent("configuration.json"))
        var configuration = CubeConfiguration()
        configuration.autoRotatesWhenIdle = false
        configuration.appearance = CubeThemePreset.prism.appearance(glowIntensity: 1)
        for face in CubeFace.allCases {
            for name in ["Messages", "Calendar", "Music", "Notes"] {
                try configuration.add(LauncherItem(url: URL(fileURLWithPath: "/System/Applications/\(name).app"),
                    name: name, kind: .application), to: face)
            }
        }
        try store.save(configuration)
        let model = AppModel(store: store)
        let view = CubeView(model: model)
        let window = NSPanel(contentRect: NSRect(x: 160, y: 160, width: 560, height: 420),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 560, height: 420)
        view.environment.background = .color(.clear)
        view.cube.orientation = CubeRotation.snapped(to: .front)
        window.orderFrontRegardless()
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/readme-theme-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let context = try #require(CGContext(data: nil, width: 128, height: 64,
            bitsPerComponent: 8, bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.88, green: 0.94, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
        let environmentImage = try #require(context.makeImage())
        view.environment.lighting.resource = try await EnvironmentResource(equirectangular: environmentImage)
        // Broad, cool studio illumination reveals the unchanged glass shell on dark pages.
        // Keep it out of the runtime app and retain a fully transparent canvas.
        view.environment.lighting.intensityExponent = 6
        func capture() async throws -> CGImage {
            let image: NSImage? = await withCheckedContinuation { continuation in
                view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
            }
            let cgImage = try #require(image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            #expect(bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0)
            #expect(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: bitmap.pixelsHigh - 1)?.alphaComponent == 0)
            return cgImage
        }
        for (preset, hovered, name) in [(CubeThemePreset.prism, true, "hover"),
                                        (.auroraFlow, true, "aurora"), (.prism, false, "idle")] {
            model.change { $0.appearance = preset.appearance(glowIntensity: 1) }
            view.refreshAppearance()
            view.setHovered(hovered)
            try await Task.sleep(for: .milliseconds(1300))
            let bitmap = NSBitmapImageRep(cgImage: try await capture())
            #expect(bitmap.pixelsWide >= 560 && bitmap.pixelsHigh >= 420)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent("cube-\(name)-dark.png"))
        }
        let animationSize = NSSize(width: 760 / window.backingScaleFactor, height: 570 / window.backingScaleFactor)
        window.setContentSize(animationSize)
        view.frame = NSRect(origin: .zero, size: animationSize)
        model.change { $0.autoRotatesWhenIdle = true }
        let motionURL = output.appendingPathComponent("cube-motion-dark.png")
        let destination = try #require(CGImageDestinationCreateWithURL(motionURL as CFURL,
            UTType.png.identifier as CFString, 36, nil))
        CGImageDestinationSetProperties(destination,
            [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary)
        var hoverPose = view.cube.orientation
        for index in 0..<36 {
            view.setHovered(index >= 12 && index < 24)
            if index == 12 { hoverPose = view.cube.orientation }
            try await Task.sleep(for: .milliseconds(200))
            if index >= 12 && index < 24 {
                #expect(simd_length(view.cube.orientation.vector - hoverPose.vector) < 0.00001)
            }
            CGImageDestinationAddImage(destination, try await capture(),
                [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.2]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        let decoded = try #require(CGImageSourceCreateWithURL(motionURL as CFURL, nil))
        #expect(CGImageSourceGetCount(decoded) == 36)
    }
}
