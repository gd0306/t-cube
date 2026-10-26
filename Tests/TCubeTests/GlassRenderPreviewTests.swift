import AppKit
import RealityKit
import CubeCore
import Testing
import simd
import ImageIO
import UniformTypeIdentifiers
@testable import TCube

/// Opt-in visual QA renders this app's scene, without controlling another application.
@MainActor
struct GlassRenderPreviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_RENDER_PREVIEWS"] == "1"))
    func exportPrismGlassAndMotion() async throws {
        _ = NSApplication.shared
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigurationStore(url: temporary.appendingPathComponent("configuration.json"))
        var configuration = CubeConfiguration()
        configuration.appearance = CubeThemePreset.prism.appearance(glowIntensity: 1)
        let apps = ["/System/Applications/Messages.app", "/System/Applications/Calendar.app", "/System/Applications/Music.app", "/System/Applications/Notes.app"]
        for face in CubeFace.allCases {
            for path in apps {
                try configuration.add(LauncherItem(url: URL(fileURLWithPath: path, isDirectory: true), name: URL(fileURLWithPath: path).lastPathComponent, kind: .application), to: face)
            }
        }
        try store.save(configuration)
        let model = AppModel(store: store)
        let view = CubeView(model: model)
        let frame = CGRect(x: 160, y: 160, width: 440, height: 440)
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: temporary) }
        window.contentView = view
        view.frame = CGRect(origin: .zero, size: frame.size)
        view.setHovered(true)
        window.orderFrontRegardless()
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/glass-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let galleryBackground = NSColor(red: 0.065, green: 0.075, blue: 0.095, alpha: 1)

        let poses: [(String, simd_quatf, NSColor)] = [
            ("thin-prism-dark", CubeRotation.snapped(to: .front), NSColor(red: 0.065, green: 0.075, blue: 0.095, alpha: 1)),
            ("thin-prism-warm", CubeRotation.displayTilt * simd_quatf(angle: -0.45, axis: [1, 0, 0]), NSColor(red: 0.27, green: 0.24, blue: 0.22, alpha: 1)),
            ("thin-prism-light", CubeRotation.displayTilt * simd_quatf(angle: 0.35, axis: [0, 1, 0]), NSColor(white: 0.88, alpha: 1))
        ]
        for (name, pose, background) in poses {
            view.cube.orientation = pose
            view.environment.background = .color(background)
            try await Task.sleep(for: .milliseconds(350))
            let image: NSImage? = await withCheckedContinuation { continuation in
                view.snapshot(saveToHDR: false) { image in continuation.resume(returning: image) }
            }
            let rendered = try #require(image)
            let tiff = try #require(rendered.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            #expect(bitmap.pixelsWide >= 400 && bitmap.pixelsHigh >= 400)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("\(name).png"))
        }
        for preset in [CubeThemePreset.moonstone, .auroraFlow] {
            model.change { $0.appearance = preset.appearance(glowIntensity: 1) }
            view.refreshAppearance()
            view.cube.orientation = CubeRotation.snapped(to: .front)
            view.environment.background = .color(NSColor(red: 0.065, green: 0.075, blue: 0.095, alpha: 1))
            try await Task.sleep(for: .milliseconds(350))
            let image: NSImage? = await withCheckedContinuation { continuation in view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) } }
            let data = try #require(image?.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("thin-\(preset.rawValue).png"))
        }
        // Documentation uses one background, viewport and pose across every
        // state. Keep the varied-background QA captures above as well.
        let gallerySize = NSSize(width: 560, height: 420)
        window.setContentSize(gallerySize)
        view.frame = NSRect(origin: .zero, size: gallerySize)
        view.cube.orientation = CubeRotation.snapped(to: .front)
        view.environment.background = .color(galleryBackground)
        for (preset, name) in [(CubeThemePreset.prism, "readme-hover"), (.auroraFlow, "readme-aurora")] {
            model.change { $0.appearance = preset.appearance(glowIntensity: 1) }
            view.refreshAppearance()
            view.setHovered(true)
            try await Task.sleep(for: .milliseconds(350))
            let image: NSImage? = await withCheckedContinuation { continuation in view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) } }
            let data = try #require(image?.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("\(name).png"))
        }
        model.change { $0.appearance = CubeThemePreset.prism.appearance(glowIntensity: 1) }
        view.refreshAppearance()
        view.setHovered(false)
        view.cube.orientation = CubeRotation.snapped(to: .front)
        view.environment.background = .color(galleryBackground)
        try await Task.sleep(for: .milliseconds(1300))
        let idle: NSImage? = await withCheckedContinuation { continuation in
            view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        let idleData = try #require(idle?.tiffRepresentation)
        let idleBitmap = try #require(NSBitmapImageRep(data: idleData))
        let backgroundColor = try #require(idleBitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB))
        var visibleEdgeSamples = 0
        for y in stride(from: 0, to: idleBitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: idleBitmap.pixelsWide, by: 2) {
                guard let pixel = idleBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(pixel.redComponent - backgroundColor.redComponent) + abs(pixel.greenComponent - backgroundColor.greenComponent) + abs(pixel.blueComponent - backgroundColor.blueComponent) > 0.08 {
                    visibleEdgeSamples += 1
                }
            }
        }
        #expect(visibleEdgeSamples > 100, "Idle glass edges must remain visible without icons")
        let idlePNG = try #require(idleBitmap.representation(using: .png, properties: [:]))
        try idlePNG.write(to: output.appendingPathComponent("thin-glass-idle.png"))
        try idlePNG.write(to: output.appendingPathComponent("readme-idle.png"))

        view.environment.background = .color(galleryBackground)
        let flow = try #require(view.cube.findEntity(named: "prism-flow") as? ModelEntity)
        let startingMaterial = try #require(flow.model?.materials.first as? UnlitMaterial)
        let startingPhase = startingMaterial.textureCoordinateTransform.offset.x
        let pose = view.cube.orientation
        let gifURL = output.appendingPathComponent("thin-glass-motion.gif")
        let destination = try #require(CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, 24, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<24 {
            view.setHovered(index >= 6)
            try await Task.sleep(for: .milliseconds(100))
            let frame: NSImage? = await withCheckedContinuation { continuation in
                view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
            }
            let cgImage = try #require(frame?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            if [0, 12, 23].contains(index) {
                let still = NSBitmapImageRep(cgImage: cgImage)
                try #require(still.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("thin-glass-motion-\(index).png"))
            }
            CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        try Data(contentsOf: gifURL).write(to: output.appendingPathComponent("readme-motion.gif"))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let endingMaterial = try #require(flow.model?.materials.first as? UnlitMaterial)
            #expect(abs(endingMaterial.textureCoordinateTransform.offset.x - startingPhase) > 0.005, "The visible scene must actually advance the light")
        }
        #expect(abs(simd_dot(pose.vector, view.cube.orientation.vector)) > 0.99999, "Light animation must not move the user's chosen pose")
    }
}
