import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
private final class VisibleTestPanel: NSPanel {
    override var occlusionState: NSWindow.OcclusionState { .visible }
}

@MainActor
@Suite(.serialized)
struct FrozenFrameMemoryTests {
    @Test func inputWakeReleasesPreviouslyDisplayedFrozenImage() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("configuration.json")))
        let cube = CubeView(model: model)
        let image = NSImage(size: NSSize(width: 8, height: 8))
        let surface = CubeSurfaceView(cubeView: cube, frameCapture: { complete in complete(image) })
        let window = VisibleTestPanel(contentRect: NSRect(x: 120, y: 120, width: 164, height: 164), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.enableRenderingManagement()
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; model.stopThemeCycle() }
        #expect(surface.resumeRendering(forInput: true))
        cube.staticFrameRequested?()
        let holder = try #require(surface.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(holder.image === image)
        #expect(surface.hasFrozenFrame)
        #expect(surface.resumeRendering(forInput: true))
        #expect(holder.image == nil)
        #expect(!surface.hasFrozenFrame)
    }

    @Test func hiddenWindowKeepsFallbackForNextWarmup() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("configuration.json")))
        let cube = CubeView(model: model)
        let image = NSImage(size: NSSize(width: 8, height: 8))
        let surface = CubeSurfaceView(cubeView: cube, frameCapture: { complete in complete(image) })
        let window = VisibleTestPanel(contentRect: NSRect(x: 120, y: 120, width: 164, height: 164), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.enableRenderingManagement()
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; model.stopThemeCycle() }
        #expect(surface.resumeRendering(forInput: true))
        cube.staticFrameRequested?()
        let holder = try #require(surface.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(holder.image === image)
        window.orderOut(nil)
        surface.synchronizeRenderingVisibility()
        #expect(holder.image === image)
        #expect(surface.hasFrozenFrame)
        window.orderFrontRegardless()
        #expect(surface.resumeRendering(forInput: true))
        #expect(cube.superview === surface)
        #expect(cube.alphaValue == 1)
    }
    @Test func automaticWakeRetainsFallbackWhileLiveFramesWarm() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("configuration.json")))
        let cube = CubeView(model: model)
        let image = NSImage(size: NSSize(width: 8, height: 8))
        let surface = CubeSurfaceView(cubeView: cube, frameCapture: { complete in complete(image) })
        let window = VisibleTestPanel(contentRect: NSRect(x: 120, y: 120, width: 164, height: 164), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.enableRenderingManagement()
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; model.stopThemeCycle() }
        #expect(surface.resumeRendering(forInput: true))
        cube.staticFrameRequested?()
        let holder = try #require(surface.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(surface.hasFrozenFrame)
        #expect(surface.resumeRendering())
        #expect(surface.hasFrozenFrame)
        #expect(holder.image === image)
        #expect(cube.alphaValue == 0)
    }

    @Test func cancelledTransitionReleasesItsOldFrame() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        var configuration = CubeConfiguration()
        configuration.autoRotatesWhenIdle = false
        try store.save(configuration)
        let model = AppModel(store: store)
        let cube = CubeView(model: model)
        var captures: [(NSImage?) -> Void] = []
        let surface = CubeSurfaceView(cubeView: cube, frameCapture: { captures.append($0) })
        let window = VisibleTestPanel(contentRect: NSRect(x: 120, y: 120, width: 164, height: 164), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.enableRenderingManagement()
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; model.stopThemeCycle() }
        #expect(surface.resumeRendering(forInput: true))
        cube.staticFrameRequested?()
        let pendingInitial = captures.popLast()
        let initial = try #require(pendingInitial)
        var source: NSImage? = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        weak var weakSource = source
        initial(source)
        source = nil
        #expect(surface.hasFrozenFrame)
        model.change { $0.appearance = CubeThemePreset.ocean.appearance(glowIntensity: 0.7) }
        cube.refreshAppearance()
        cube.advanceAnimations(deltaTime: 0.1, reducedMotion: false)
        cube.advanceAnimations(deltaTime: 0.1, reducedMotion: false)
        let pendingTarget = captures.popLast()
        let target = try #require(pendingTarget)
        target(NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        })
        #expect(surface.resumeRendering(forInput: true))
        for _ in 0..<10 where weakSource != nil { try await Task.sleep(for: .milliseconds(30)) }
        #expect(weakSource == nil)
    }

}
