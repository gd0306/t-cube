import AppKit
import Testing
import CubeCore
@testable import TCube

@MainActor
struct RenderingLifecycleTests {
    @Test func staticSnapshotDetachesRendererAndMouseEntryRestoresLiveView() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
        var config = CubeConfiguration()
        config.autoRotatesWhenIdle = true
        try store.save(config)
        let model = AppModel(store: store)
        let view = CubeView(model: model)
        view.idlePowerSavingEnabled = true
        let surface = CubeSurfaceView(cubeView: view)
        let visible = try #require(NSScreen.main?.visibleFrame)
        let window = NSPanel(contentRect: NSRect(x: visible.minX + 20, y: visible.minY + 20, width: 164, height: 164), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 10)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.enableRenderingManagement()
        defer { window.orderOut(nil); window.contentView = nil; model.stopThemeCycle() }
        window.orderFrontRegardless()
        _ = surface.resumeRendering(forInput: true)
        let deadline = Date().addingTimeInterval(8)
        while !surface.hasFrozenFrame && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(surface.hasFrozenFrame, "A real ARView snapshot must be retained before detaching a visible static renderer")
        #expect(surface.rendererDetached)
        #expect(view.window == nil)
        #expect(!view.animationUpdatesRunning)
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 82, y: 82), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
        surface.input.mouseEntered(with: event)
        #expect(view.window === window)
        #expect(!surface.rendererDetached)
        #expect(!surface.hasFrozenFrame)
        #expect(view.animationUpdatesRunning)
    }

    @Test func appearanceRefreshKeepsPreviousFrameUntilNewStaticFrameIsReady() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
        var config = CubeConfiguration()
        config.autoRotatesWhenIdle = false
        config.appearance = CubeThemePreset.prism.appearance(glowIntensity: 0.7)
        try store.save(config)
        let model = AppModel(store: store)
        let view = CubeView(model: model)
        view.idlePowerSavingEnabled = true
        let surface = CubeSurfaceView(cubeView: view)
        let area = try #require(NSScreen.main?.visibleFrame)
        let window = NSPanel(contentRect: NSRect(x: area.minX + 20, y: area.minY + 20, width: 164, height: 164), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 10)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.enableRenderingManagement()
        defer { window.orderOut(nil); window.contentView = nil; model.stopThemeCycle() }
        window.orderFrontRegardless()
        _ = surface.resumeRendering(forInput: true)
        var deadline = Date().addingTimeInterval(8)
        while !surface.hasFrozenFrame && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(surface.hasFrozenFrame)
        model.change { $0.appearance = CubeThemePreset.auroraFlow.appearance(glowIntensity: 0.7) }
        view.refreshAppearance()
        #expect(surface.hasFrozenFrame, "A theme tick must not expose the warming RealityKit surface")
        #expect(view.alphaValue == 0, "New frames prepare without adding light behind the old transparent image")
        deadline = Date().addingTimeInterval(8)
        while (!surface.rendererDetached || surface.isThemeTransitioning) && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(surface.hasFrozenFrame)
        #expect(surface.rendererDetached)
        #expect(!view.animationUpdatesRunning)
        let image = try #require(surface.subviews.compactMap { $0 as? NSImageView }.first?.image)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        #expect(bitmap.pixelsWide > 0)
        #expect((0..<bitmap.pixelsHigh).contains { y in (0..<bitmap.pixelsWide).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 } }, "Prepared frames must contain the cube even while its view is transparent")
    }

    @Test func hiddenRendererDetachesAndInputCanReattachIt() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(store: ConfigurationStore(url: folder.appendingPathComponent("configuration.json")))
        let view = CubeView(model: model)
        let surface = CubeSurfaceView(cubeView: view)
        let window = NSPanel(contentRect: NSRect(x: 120, y: 120, width: 164, height: 164), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.enableRenderingManagement()
        defer { window.orderOut(nil); window.contentView = nil; model.stopThemeCycle() }
        surface.synchronizeRenderingVisibility()
        #expect(surface.rendererDetached)
        #expect(view.superview == nil)
        #expect(!view.animationUpdatesRunning)
        window.orderFrontRegardless()
        surface.synchronizeRenderingVisibility()
        // WindowServer occlusion notification is asynchronous; resume only if actually visible.
        if window.occlusionState.contains(.visible) {
            #expect(!surface.rendererDetached)
            #expect(view.superview === surface)
            #expect(view.animationUpdatesRunning)
        }
        window.orderOut(nil)
        surface.synchronizeRenderingVisibility()
        #expect(surface.rendererDetached)
        #expect(!view.animationUpdatesRunning)
    }
}
