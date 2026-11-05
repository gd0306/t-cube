import AppKit
import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import TCube

@MainActor
final class EdgeDockAnimationTests: XCTestCase {
    private func advance(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.01))) }
    }

    func testExportNativeDockingMotion() throws {
        guard ProcessInfo.processInfo.environment["TCUBE_DOCK_PREVIEWS"] == "1" else { throw XCTSkip("Opt-in native render export") }
        let fixture = try Fixture(usesRealRenderer: true)
        defer { fixture.close() }
        advance(0.4)
        var image: NSImage?
        fixture.surface.captureDockingFrame { image = $0 }
        let deadline = Date().addingTimeInterval(3)
        while image == nil && Date() < deadline { advance(0.02) }
        let source = try XCTUnwrap(image)
        let animator = EdgeDockAnimator()
        defer { animator.shutdown() }
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/edge-dock-previews")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(folder.appendingPathComponent("mac-edge-dock.gif") as CFURL, UTType.gif.identifier as CFString, 60, nil))
        CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let handle = CGRect(x: fixture.frame.minX - 24, y: fixture.frame.midY - 28, width: 10, height: 56)
        var count = 0
        var timing = "direction,index,elapsed,width,opacity,animationBegin,layerTime\n"
        for toEdge in [true, false] {
            animator.animate(image: source, cube: fixture.frame, handle: handle, toEdge: toEdge, completion: {})
            let window = try XCTUnwrap(NSApp.windows.first { $0.title == "T-Cube · 贴边过渡" })
            let layer = try XCTUnwrap(window.contentView?.layer)
            let duration = toEdge ? 0.36 : 0.46
            let start = Date()
            for index in 0..<30 {
                let target = Double(index) * duration / 30
                while Date().timeIntervalSince(start) < target { advance(0.001) }
                let width = Int(window.frame.width * 2), height = Int(window.frame.height * 2)
                let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(NSColor(srgbRed: 0.15, green: 0.17, blue: 0.20, alpha: 1).cgColor)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.scaleBy(x: 2, y: 2)
                (layer.presentation() ?? layer).render(in: context)
                let frame = try XCTUnwrap(context.makeImage())
                if let body = layer.sublayers?.first {
                    let shown = body.presentation() ?? body
                    timing += "\(toEdge),\(index),\(Date().timeIntervalSince(start)),\(shown.bounds.width),\(shown.opacity),\(body.animation(forKey: "TCube.edgeDock")?.beginTime ?? -1),\(body.convertTime(CACurrentMediaTime(), from: nil))\n"
                    if index == 29 && !toEdge {
                        XCTAssertGreaterThan(shown.bounds.width, fixture.frame.width * 0.95, "The compositor must reach the cube before handoff")
                    }
                }
                CGImageDestinationAddImage(output, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: duration / 30]] as CFDictionary)
                if [3, 12, 21].contains(index) {
                    let png = try XCTUnwrap(CGImageDestinationCreateWithURL(folder.appendingPathComponent("\(toEdge ? "absorb" : "reveal")-\(index).png") as CFURL, UTType.png.identifier as CFString, 1, nil))
                    CGImageDestinationAddImage(png, frame, nil)
                    XCTAssertTrue(CGImageDestinationFinalize(png))
                }
                count += 1
            }
            advance(0.1)
        }
        XCTAssertEqual(count, 60)
        XCTAssertTrue(CGImageDestinationFinalize(output))
        try timing.write(to: folder.appendingPathComponent("timing.csv"), atomically: true, encoding: .utf8)
    }

    func testReversingAndHidingDuringAnimationCannotLeaveAVisibleGhostOrSaveTemporaryGeometry() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        var saves = 0
        fixture.hover.onRestingPositionChange = { _ in saves += 1 }
        fixture.collapse()
        XCTAssertTrue(fixture.coordinator.isTransitioning)
        XCTAssertFalse(fixture.panel.isVisible)
        advance(0.09)
        fixture.coordinator.reveal()
        XCTAssertTrue(fixture.coordinator.isTransitioning)
        XCTAssertTrue(fixture.panel.isVisible)
        XCTAssertLessThan(fixture.panel.alphaValue, 1)
        fixture.hover.pointerChanged(to: CGPoint(x: fixture.frame.midX, y: fixture.frame.midY))
        XCTAssertEqual(fixture.panel.frame, fixture.frame, "Hover enlargement must not resize the real panel behind the transition")
        fixture.coordinator.setUserVisible(false)
        advance(0.6)
        XCTAssertFalse(fixture.panel.isVisible)
        XCTAssertFalse(fixture.coordinator.handleIsVisible)
        XCTAssertFalse(fixture.coordinator.isTransitioning)
        XCTAssertFalse(NSApp.windows.contains { $0.title == "T-Cube · 贴边过渡" && $0.isVisible })
        XCTAssertEqual(fixture.hover.restingFrame, fixture.frame)
        XCTAssertEqual(saves, 0)
    }

    func testCompletedTransitionsDetachTheRendererAndReuseOneOverlay() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.surface.enableRenderingManagement()
        fixture.coordinator.didChangePresentation = { fixture.surface.synchronizeRenderingVisibility() }
        var windowCount: Int?
        for _ in 0..<3 {
            fixture.collapse()
            advance(0.43)
            XCTAssertTrue(fixture.coordinator.handleIsVisible)
            XCTAssertFalse(fixture.coordinator.isTransitioning)
            XCTAssertTrue(fixture.surface.rendererDetached)
            XCTAssertFalse(fixture.surface.cubeView.animationUpdatesRunning)
            if let windowCount { XCTAssertEqual(NSApp.windows.count, windowCount) }
            else { windowCount = NSApp.windows.count }
            fixture.coordinator.reveal()
            advance(0.1)
            XCTAssertTrue(fixture.surface.rendererDetached, "The compositor transition must not wake hidden 3D rendering")
            XCTAssertFalse(fixture.surface.cubeView.animationUpdatesRunning)
            advance(0.44)
            XCTAssertTrue(fixture.panel.isVisible)
            XCTAssertEqual(fixture.panel.alphaValue, 1)
            XCTAssertFalse(fixture.panel.ignoresMouseEvents)
            XCTAssertFalse(fixture.coordinator.handleIsVisible)
            XCTAssertFalse(fixture.coordinator.isTransitioning)
            XCTAssertEqual(fixture.hover.restingFrame, fixture.frame)
        }
    }

    func testMissingCaptureFallsBackAndReducedMotionSkipsSpatialAnimation() throws {
        let stalled = try Fixture(capture: { _ in })
        stalled.collapse()
        advance(0.25)
        XCTAssertFalse(stalled.coordinator.isTransitioning)
        XCTAssertTrue(stalled.coordinator.handleIsVisible)
        XCTAssertFalse(stalled.panel.isVisible)
        stalled.coordinator.reveal()
        XCTAssertEqual(stalled.panel.alphaValue, 1)
        stalled.close()
        var captures = 0
        let reduced = try Fixture(motionAllowed: false, capture: { _ in captures += 1 })
        defer { reduced.close() }
        reduced.collapse()
        XCTAssertTrue(reduced.coordinator.handleIsVisible)
        XCTAssertFalse(reduced.coordinator.isTransitioning)
        reduced.coordinator.reveal()
        XCTAssertEqual(reduced.panel.alphaValue, 1)
        XCTAssertEqual(captures, 0)
    }

    func testResizingDuringAbsorptionCancelsTheOldGeometryEvenWhenTheHandleDoesNotMove() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.collapse()
        XCTAssertTrue(fixture.coordinator.isTransitioning)
        fixture.hover.configure(baseSize: NSSize(width: 180, height: 180), settings: .init())
        fixture.coordinator.tick()
        XCTAssertFalse(fixture.coordinator.isTransitioning, "The old-size image must not finish over a new-size cube")
        XCTAssertTrue(fixture.coordinator.handleIsVisible)
        fixture.coordinator.reveal()
        advance(0.55)
        XCTAssertEqual(fixture.panel.frame, fixture.hover.restingFrame)
        XCTAssertEqual(fixture.panel.frame.width, 180)
    }

    func testCollapseWaitsForItsOwnFrameAndLateCaptureCannotHideARevealedCube() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: folder.lastPathComponent))
        defer { defaults.removePersistentDomain(forName: folder.lastPathComponent) }
        let model = AppModel(store: .init(url: folder.appendingPathComponent("configuration.json")))
        defer { model.stopThemeCycle() }
        var captured: ((NSImage?) -> Void)?
        let surface = CubeSurfaceView(cubeView: CubeView(model: model), frameCapture: { captured = $0 })
        let area = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let frame = CGRect(x: area.minX + 24, y: area.midY - 82, width: 164, height: 164)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.contentView = surface; panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.contentView = nil }
        let hover = CubeHoverController(window: panel, settings: .init(), screens: { [area] })
        let settings = DesktopAutoHideSettings(defaults: defaults)
        var now = 0.0
        let coordinator = DesktopAutoHideCoordinator(panel: panel, hover: hover, settings: settings,
            screens: { [area] }, pointer: { CGPoint(x: area.maxX - 100, y: area.minY + 100) },
            fullscreen: { _ in false }, clock: { now }, schedulesPolling: false, motionAllowed: { true })
        defer { coordinator.stop() }
        coordinator.start(); settings.setEdgeCollapse(true)
        now = 1; coordinator.tick()
        XCTAssertEqual(coordinator.presentation, .edge)
        XCTAssertTrue(panel.isVisible, "Keep the real cube visible until the transition image is ready")
        let completion = try XCTUnwrap(captured)
        coordinator.reveal()
        completion(NSImage(size: frame.size))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 1)
        XCTAssertFalse(coordinator.handleIsVisible)
        XCTAssertEqual(hover.restingFrame, frame)
    }
}

@MainActor
private final class Fixture {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let model: AppModel
    let surface: CubeSurfaceView
    let panel: NSPanel
    let hover: CubeHoverController
    let settings: DesktopAutoHideSettings
    let frame: CGRect
    let coordinator: DesktopAutoHideCoordinator
    private let time: Time
    private final class Time { var now = 0.0 }

    init(motionAllowed: Bool = true, usesRealRenderer: Bool = false, capture: ((@escaping (NSImage?) -> Void) -> Void)? = nil) throws {
        _ = NSApplication.shared
        defaults = try XCTUnwrap(UserDefaults(suiteName: folder.lastPathComponent))
        model = AppModel(store: .init(url: folder.appendingPathComponent("configuration.json")))
        surface = CubeSurfaceView(cubeView: CubeView(model: model), frameCapture: usesRealRenderer ? nil : capture ?? { $0(NSImage(size: NSSize(width: 164, height: 164))) })
        let area = try XCTUnwrap(NSScreen.main?.visibleFrame)
        frame = CGRect(x: area.minX + 24, y: area.midY - 82, width: 164, height: 164)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.contentView = surface; panel.orderFrontRegardless()
        hover = CubeHoverController(window: panel, settings: .init(), screens: { [area] })
        settings = DesktopAutoHideSettings(defaults: defaults)
        let time = Time(); self.time = time
        coordinator = DesktopAutoHideCoordinator(panel: panel, hover: hover, settings: settings,
            screens: { [area] }, pointer: { CGPoint(x: area.maxX - 100, y: area.minY + 100) },
            fullscreen: { _ in false }, clock: { time.now }, schedulesPolling: false, motionAllowed: { motionAllowed })
        coordinator.start(); settings.setEdgeCollapse(true)
    }

    func collapse() { time.now += 1; coordinator.tick(); time.now += 1; coordinator.tick() }

    func close() {
        coordinator.didChangePresentation = nil
        coordinator.stop(); model.stopThemeCycle()
        panel.orderOut(nil); panel.contentView = nil
        defaults.removePersistentDomain(forName: folder.lastPathComponent)
        try? FileManager.default.removeItem(at: folder)
    }
}
