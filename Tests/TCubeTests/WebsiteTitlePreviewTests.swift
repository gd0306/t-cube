import AppKit
import CubeCore
import SwiftUI
import Testing
import simd
@testable import TCube

@MainActor
struct WebsiteTitlePreviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_WEBSITE_PREVIEWS"] == "1"))
    func websiteTitlesRemainReadableOnTheCurvedCubeAndExpandedPanel() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        var config = CubeConfiguration()
        config.autoRotatesWhenIdle = false
        for (index, name) in ["工作仓库", "个人仓库", "这是一段需要自动省略的网页长标题", "设计 👩🏽‍💻 资料"].enumerated() {
            try config.place(WebsiteTarget.item(title: name, address: "https://example.test/page/\(index)"), to: .front, slot: index)
        }
        try store.save(config)
        let model = AppModel(store: store)
        defer { model.stopThemeCycle() }
        let view = CubeView(model: model)
        let window = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 440, height: 440), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        view.cube.orientation = CubeRotation.snapped(to: .front)
        view.setHovered(true)
        defer { view.suspendAnimationUpdates(); window.orderOut(nil); window.contentView = nil }
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/website-title-previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, color) in [("dark", NSColor(white: 0.08, alpha: 1)), ("light", NSColor.white)] {
            view.environment.background = .color(color)
            try await Task.sleep(for: .milliseconds(400))
            let snapshot: NSImage? = await withCheckedContinuation { continuation in
                view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
            }
            let bitmap = try #require(snapshot?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("website-cube-\(name).png"))
        }
        let renderer = ImageRenderer(content: ExpandedFaceView(model: model, face: .front, close: {})
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        let expanded = try #require(renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        #expect(expanded.colorAt(x: 0, y: 0)?.alphaComponent == 0, "The README example must not add a rectangular backdrop")
        try #require(expanded.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("website-expanded.png"))
        let atlas = try #require(CubeTheme.faceImage(group: config.group(for: .front), ordinal: 0))
        try #require(NSBitmapImageRep(cgImage: atlas).representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("website-atlas.png"))
    }
}
