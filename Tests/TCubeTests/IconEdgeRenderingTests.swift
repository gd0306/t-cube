import AppKit
import CubeCore
import ImageIO
import RealityKit
import Testing
import simd
@testable import TCube

@MainActor
struct IconEdgeRenderingTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_ICON_EDGE_DIAGNOSTICS"] == "1" || ProcessInfo.processInfo.environment["TCUBE_RENDER_PREVIEWS"] == "1"))
    func whiteDecalShouldNotGrowADarkFringeOnAWhiteBackdrop() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("settings.json")))
        let view = CubeView(model: model)
        let window = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 440, height: 440), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 440, height: 440)
        view.environment.background = .color(.white)
        view.cube.findEntity(named: "cube-aura")?.isEnabled = false
        view.cube.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        view.setHovered(true)
        let synthetic = NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { _ in
            NSColor.clear.setFill()
            NSRect(x: 0, y: 0, width: 1024, height: 1024).fill(using: .copy)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: FaceLayout.iconRect(0), xRadius: 40, yRadius: 40).fill()
            return true
        }
        let image = try #require(synthetic.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let prepared = try #require(IconTexture.preparedImage(from: image))
        let front = try #require(view.cube.findEntity(named: "front") as? ModelEntity)
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        let texture = try await TextureResource(image: prepared, options: .init(semantic: .color))
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        material.faceCulling = .back
        material.writesDepth = false
        front.model?.materials = [material]
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        let snapshot: NSImage? = await withCheckedContinuation { continuation in
            view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        let bitmap = try #require(snapshot?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/glass-previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("icon-edge-white-fixed.png"))
        var darkest: CGFloat = 1
        var fringePixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let brightness = min(color.redComponent, min(color.greenComponent, color.blueComponent))
                darkest = min(darkest, brightness)
                if brightness < 0.95 { fringePixels += 1 }
            }
        }
        print("White decal diagnostic: darkest=\(darkest), fringe pixels=\(fringePixels)")
        #expect(fringePixels == 0, "A white icon on white must not acquire a black sampling border")

        // A transparent or missing decal would also pass the white-background
        // check, so confirm that its opaque center still renders on black.
        view.environment.background = .color(.black)
        try await Task.sleep(for: .milliseconds(200))
        let darkSnapshot: NSImage? = await withCheckedContinuation { continuation in
            view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        let darkBitmap = try #require(darkSnapshot?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        for y in stride(from: 0, to: darkBitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: darkBitmap.pixelsWide, by: 4) {
                if let color = darkBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.redComponent > 0.95 { visibleSamples += 1 }
            }
        }
        #expect(visibleSamples > 50, "Removing a fringe must not remove the icon")
        try #require(darkBitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("icon-edge-dark-fixed.png"))
    }
}
