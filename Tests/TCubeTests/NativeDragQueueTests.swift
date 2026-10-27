import AppKit
import XCTest
import CubeCore
import simd
@testable import TCube

/// AppKit's nested event tracking is exercised synchronously, outside Swift
/// Testing's async executor, using events queued only in this test process.
final class NativeDragQueueTests: XCTestCase {
    func testControlDragUsesSmallFrameAndSavesPosition() throws {
        try MainActor.assumeIsolated { try Self.controlDrag(releaseControlBeforeMouseUp: false) }
    }

    func testControlDragDoesNotGrowWhenControlReleasedBeforeMouseUp() throws {
        try MainActor.assumeIsolated { try Self.controlDrag(releaseControlBeforeMouseUp: true) }
    }

    @MainActor
    private static func controlDrag(releaseControlBeforeMouseUp: Bool) throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        let model = AppModel(store: store)
        let view = CubeView(model: model)
        let surface = CubeSurfaceView(cubeView: view)
        let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let start = CGPoint(x: visible.minX + 200, y: visible.minY + 200)
        let window = NSPanel(contentRect: CGRect(origin: start, size: CGSize(width: 100, height: 100)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.contentView = surface
        window.orderFrontRegardless()
        let hover = CubeHoverController(window: window, settings: CubeHoverSettings(multiplier: 4))
        surface.input.modifierFlagsChanged = { hover.modifierFlagsChanged($0, at: $1) }
        view.interactionChanged = { hover.setInteractionActive($0) }
        hover.onRestingPositionChange = { model.savePosition($0) }
        var frameAtCommit: CGRect?
        view.positionCommitted = { frameAtCommit = $0; hover.commitMovedFrame($0) }
        var openedSettings = false
        var openedFace = false
        view.editRequested = { openedSettings = true }
        view.faceRequested = { _, _ in openedFace = true }
        hover.pointerChanged(to: CGPoint(x: start.x + 50, y: start.y + 50))
        let windowNumber = window.windowNumber
        func event(_ type: NSEvent.EventType, _ point: CGPoint, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        let flags: NSEvent.ModifierFlags = releaseControlBeforeMouseUp ? [] : [.control]
        // Construct subsequent events after the panel shrinks. AppKit encodes
        // synthetic event Y relative to the window height at creation time.
        RunLoop.main.perform(inModes: [.eventTracking]) {
            MainActor.assumeIsolated {
                for (type, point) in [(NSEvent.EventType.leftMouseDragged, CGPoint(x: 130, y: 110)), (.leftMouseUp, CGPoint(x: 90, y: 85))] {
                    if let queued = NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) {
                        NSApp.postEvent(queued, atStart: false)
                    }
                }
            }
        }
        surface.input.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 360, y: 340), [.control]))
        XCTAssertEqual(frameAtCommit, CGRect(x: start.x + 160, y: start.y + 130, width: 100, height: 100))
        XCTAssertEqual(try store.load().windowPosition, WindowPosition(x: start.x + 160, y: start.y + 130))
        let finalWidth = window.frame.width
        XCTAssertEqual(finalWidth, releaseControlBeforeMouseUp ? 400 : 100)
        XCTAssertFalse(openedSettings)
        XCTAssertFalse(openedFace)
    }

    func testControlClickDoesNotOpenSettingsOrFace() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("configuration.json")))
            let view = CubeView(model: model)
            let surface = CubeSurfaceView(cubeView: view)
            let window = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 100, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
            window.contentView = surface
            window.orderFrontRegardless()
            var openedSettings = false
            var openedFace = false
            view.editRequested = { openedSettings = true }
            view.faceRequested = { _, _ in openedFace = true }
            let windowNumber = window.windowNumber
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 50, y: 50), modifierFlags: [.control], timestamp: 0, windowNumber: windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            NSApp.postEvent(try event(.leftMouseUp), atStart: false)
            surface.input.mouseDown(with: try event(.leftMouseDown))
            XCTAssertFalse(openedSettings, "Control-click is reserved for moving the small cube")
            XCTAssertFalse(openedFace)
        }
    }

    func testRightDragConsumesNativeEventsAndRotatesWithoutMoving() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
            let model = AppModel(store: store)
            let view = CubeView(model: model)
            let surface = CubeSurfaceView(cubeView: view)
            let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
            let start = CGPoint(x: visible.minX + 100, y: visible.minY + 100)
            let window = NSPanel(contentRect: CGRect(origin: start, size: CubeTheme.windowSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
            window.contentView = surface
            window.orderFrontRegardless()
            let windowNumber = window.windowNumber
            func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                let result = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)
                return try XCTUnwrap(result)
            }
            let initialRotation = view.cube.orientation
            var openedSettings = false
            view.editRequested = { openedSettings = true }
            NSApp.postEvent(try event(.rightMouseDragged, CGPoint(x: 90, y: 75)), atStart: false)
            NSApp.postEvent(try event(.rightMouseUp, CGPoint(x: 100, y: 80)), atStart: false)
            surface.input.rightMouseDown(with: try event(.rightMouseDown, CGPoint(x: 50, y: 50)))
            XCTAssertEqual(window.frame.origin, start)
            XCTAssertLessThan(abs(simd_dot(initialRotation.vector, view.cube.orientation.vector)), 0.999)
            XCTAssertNil(try store.load().windowPosition)
            XCTAssertFalse(openedSettings)
        }
    }
}
