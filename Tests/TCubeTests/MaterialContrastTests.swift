import AppKit
import CubeCore
import RealityKit
import Testing
@testable import TCube

@MainActor
struct MaterialContrastTests {
    @Test
    func idleMaterialRemainsVisibleOnLightAndDarkBackgrounds() async throws {
        _ = NSApplication.shared
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = ConfigurationStore(url: temporary.appendingPathComponent("configuration.json"))
        var configuration = CubeConfiguration()
        configuration.autoRotatesWhenIdle = false
        try store.save(configuration)
        let model = AppModel(store: store)
        let view = CubeView(model: model)
        let frame = NSRect(x: 100, y: 100, width: 164, height: 164)
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.setHovered(false)
        view.suspendAnimationUpdates()
        window.orderFrontRegardless()
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/material-contrast")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for material in CubeMaterial.allCases {
            for preset in CubeThemePreset.allCases {
                model.change {
                    $0.appearance = preset.appearance(glowIntensity: 1)
                    $0.appearance.material = material
                }
                view.refreshAppearance()
                view.suspendAnimationUpdates()
                for (name, background) in [("white", NSColor.white), ("dark", NSColor(white: 0.08, alpha: 1))] {
                    view.environment.background = .color(background)
                    try await Task.sleep(for: .milliseconds(250))
                    let image: NSImage? = await withCheckedContinuation { continuation in
                        view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
                    }
                    let bitmap = try #require(image?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                    let backdrop = try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
                    var visible = 0
                    for y in 0..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide {
                            let pixel = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                            let contrast = max(abs(pixel.redComponent - backdrop.redComponent), abs(pixel.greenComponent - backdrop.greenComponent), abs(pixel.blueComponent - backdrop.blueComponent))
                            if contrast >= 18.0 / 255 { visible += 1 }
                        }
                    }
                    let coverage = Double(visible) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
                    let label = "\(material.rawValue)-\(preset.rawValue)-\(name)"
                    print("Material contrast \(label): \(coverage)")
                    #expect(coverage > (name == "white" ? 0.015 : 0.004), "\(label) must retain a visible body without launcher icons")
                    try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("\(label).png"))
                }
            }
        }

        // Measure transmission without an interior light thread crossing the
        // sampled center. Contrast above uses all themes at full glow.
        model.change { $0.appearance = CubeThemePreset.prism.appearance(glowIntensity: 0) }
        view.refreshAppearance()
        view.suspendAnimationUpdates()
        for face in CubeFace.allCases {
            view.cube.orientation = CubeRotation.snapped(to: face)
            var centerBrightness: [CGFloat] = []
            for background in [NSColor.white, NSColor(white: 0.08, alpha: 1)] {
                view.environment.background = .color(background)
                try await Task.sleep(for: .milliseconds(250))
                let image: NSImage? = await withCheckedContinuation { continuation in
                    view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
                }
                let bitmap = try #require(image?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                // Average a center patch: a narrow pearl reflection crossing
                // one pixel must not be mistaken for an opaque glass body.
                let radius = min(bitmap.pixelsWide, bitmap.pixelsHigh) / 16
                var brightness: CGFloat = 0
                var samples = 0
                for y in (bitmap.pixelsHigh / 2 - radius)...(bitmap.pixelsHigh / 2 + radius) {
                    for x in (bitmap.pixelsWide / 2 - radius)...(bitmap.pixelsWide / 2 + radius) {
                        let pixel = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        brightness += (pixel.redComponent + pixel.greenComponent + pixel.blueComponent) / 3
                        samples += 1
                    }
                }
                centerBrightness.append(brightness / CGFloat(samples))
            }
            let response = centerBrightness[0] - centerBrightness[1]
            print("Glass transmission \(face.rawValue): \(response)")
            #expect(response > 0.70, "The glass body must still reveal the background through its center on \(face.rawValue)")
        }
    }
}
