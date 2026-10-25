import AppKit
import XCTest
import CubeCore
@testable import TCube

/// AppKit's nested event tracking is exercised synchronously, outside Swift
/// Testing's async executor, using events queued only in this test process.
final class NativeDragQueueTests: XCTestCase {
    func testRightDragConsumesNativeEventsAndPersistsPosition() throws {
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
            NSApp.postEvent(try event(.rightMouseDragged, CGPoint(x: 90, y: 75)), atStart: false)
            NSApp.postEvent(try event(.rightMouseUp, CGPoint(x: 50, y: 50)), atStart: false)
            surface.input.rightMouseDown(with: try event(.rightMouseDown, CGPoint(x: 50, y: 50)))
            XCTAssertEqual(window.frame.origin, CGPoint(x: start.x + 40, y: start.y + 25))
            XCTAssertEqual(try store.load().windowPosition, WindowPosition(x: start.x + 40, y: start.y + 25))
        }
    }
}
