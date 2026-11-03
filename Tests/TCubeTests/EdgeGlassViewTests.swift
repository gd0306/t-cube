import AppKit
import QuartzCore
import Testing
@testable import TCube

@MainActor
@Suite(.serialized)
struct EdgeGlassViewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_EDGE_GLASS_PREVIEWS"] == "1"))
    func exportNativeGlassLayersInBothSystemAppearances() throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/edge-glass-verification")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = EdgeRevealView(motionAllowed: { false }, transparencyAllowed: { true }, windowVisible: { $0.isVisible }, reveal: {})
            let window = NSPanel(contentRect: CGRect(x: 180, y: 180, width: 10, height: 56), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view
            window.appearance = NSAppearance(named: appearance); window.orderFrontRegardless()
            defer { view.shutdown(); window.orderOut(nil); window.contentView = nil }
            view.setPresented(true); view.refreshSystemStyle(); view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let opaquePixels = (0..<bitmap.pixelsHigh).reduce(0) { total, y in
                total + (0..<bitmap.pixelsWide).filter { (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.1 }.count
            }
            #expect(opaquePixels > bitmap.pixelsWide * bitmap.pixelsHigh / 4, "Glass preview must contain visible material pixels")
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("mac-edge-\(name).png"))
        }
    }

    @Test func systemAppearanceChangesTheGlassUsingTheSameLayers() async throws {
        _ = NSApplication.shared
        let view = EdgeRevealView(motionAllowed: { true }, transparencyAllowed: { true }, windowVisible: { $0.isVisible }, reveal: {})
        let window = NSPanel(contentRect: CGRect(x: 180, y: 180, width: 10, height: 56), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 10)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        defer { view.shutdown(); window.orderOut(nil); window.contentView = nil }
        window.appearance = NSAppearance(named: .aqua); window.orderFrontRegardless()
        view.setPresented(true)
        view.refreshSystemStyle()
        let fill = try #require(view.subviews.compactMap { $0.layer as? CAGradientLayer }.first)
        let light = try #require((fill.colors as? [CGColor])?.first)
        let lightColor = try #require(NSColor(cgColor: light)?.usingColorSpace(.deviceRGB))
        #expect(lightColor.redComponent > 0.7)
        window.appearance = NSAppearance(named: .darkAqua)
        view.refreshSystemStyle()
        let dark = try #require((fill.colors as? [CGColor])?.first)
        let darkColor = try #require(NSColor(cgColor: dark)?.usingColorSpace(.deviceRGB))
        #expect(darkColor.redComponent < 0.2)
        #expect(view.subviews.compactMap { $0.layer as? CAGradientLayer }.first === fill)
        #expect(light != dark)
        #expect(view.accessibilityPerformPress())
    }

    @Test func hiddenAndReducedMotionHandlesReleaseEveryFlowAnimation() async throws {
        _ = NSApplication.shared
        var motion = true, transparency = true, occluded = false, presses = 0
        let view = EdgeRevealView(motionAllowed: { motion }, transparencyAllowed: { transparency },
            windowVisible: { $0.isVisible && !occluded }, reveal: { presses += 1 })
        let window = NSPanel(contentRect: CGRect(x: 180, y: 180, width: 10, height: 56), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 10)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        defer { view.shutdown(); window.orderOut(nil); window.contentView = nil }
        func animations(_ layer: CALayer?) -> Int {
            guard let layer else { return 0 }
            return (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) { $0 + animations($1) }
        }
        window.orderFrontRegardless(); view.setPresented(true)
        let deadline = Date().addingTimeInterval(2)
        while animations(view.layer) == 0 && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(animations(view.layer) == 1)
        for _ in 0..<40 {
            view.setPresented(false)
            #expect(animations(view.layer) == 0)
            view.setPresented(true)
            #expect(animations(view.layer) == 1)
        }
        occluded = true; view.refreshSystemStyle()
        #expect(animations(view.layer) == 0)
        occluded = false; view.refreshSystemStyle()
        #expect(animations(view.layer) == 1)
        motion = false; view.refreshSystemStyle()
        #expect(animations(view.layer) == 0)
        view.needsLayout = true; view.layoutSubtreeIfNeeded()
        let fill = try #require(view.subviews.compactMap { $0.layer as? CAGradientLayer }.first)
        let staticGleam = try #require(fill.sublayers?.first)
        #expect(staticGleam.frame.midY > 0 && staticGleam.frame.midY < fill.bounds.height,
            "Reduced-motion glass must keep its static reflection inside the capsule after layout")
        motion = true; transparency = false; view.refreshSystemStyle()
        #expect(animations(view.layer) == 0)
        let materialsHidden = view.subviews.compactMap { $0 as? NSVisualEffectView }.allSatisfy { $0.isHidden }
        #expect(materialsHidden)
        #expect(view.accessibilityPerformPress() && presses == 1)
        view.setPresented(false); window.orderOut(nil)
        #expect(animations(view.layer) == 0)
    }

    @Test func collapsedHandleUsesGlassMaterialInsteadOfAnAccentColoredSlab() throws {
        _ = NSApplication.shared
        let name = "EdgeGlassTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = DesktopAutoHideSettings(defaults: defaults)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = NSPanel(contentRect: CGRect(x: 24, y: 300, width: 164, height: 164), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        let hover = CubeHoverController(window: panel, settings: .init(), screens: { [screen] })
        var now = 0.0
        let coordinator = DesktopAutoHideCoordinator(panel: panel, hover: hover, settings: settings, screens: { [screen] },
            pointer: { CGPoint(x: 800, y: 800) }, fullscreen: { _ in false }, clock: { now }, schedulesPolling: false)
        defer { coordinator.stop() }
        coordinator.start(); settings.setEdgeCollapse(true); now = 1; coordinator.tick()
        let handle = try #require(NSApp.windows.first { $0.title == "T-Cube · 展开立方体" && $0.isVisible })
        let view = try #require(handle.contentView)
        func materials(in view: NSView) -> [NSVisualEffectView] {
            (view as? NSVisualEffectView).map { [$0] } ?? view.subviews.flatMap { materials(in: $0) }
        }
        #expect(materials(in: view).contains { $0.blendingMode == .behindWindow })
        #expect(handle.frame.size == CGSize(width: 10, height: 56))
        coordinator.reveal()
        #expect(!handle.isVisible)
    }
}
