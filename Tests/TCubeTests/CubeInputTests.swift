import AppKit
import CubeCore
import Testing
import simd
import RealityKit
@testable import TCube

@MainActor
struct CubeInputTests {
    @Test func nativeInputSurfaceAcceptsEventsAndMovesTheWindowThroughTheActualReceiver() throws {
        let (view, window, _, store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        window.ignoresMouseEvents = true
        let surface = CubeSurfaceView(cubeView: view)
        window.contentView = surface
        #expect(!window.ignoresMouseEvents)
        let receiver = try #require(surface.hitTest(CGPoint(x: 82, y: 82)))
        let isNativeInput = receiver is CubeInputOverlay
        #expect(isNativeInput)
        let start = window.frame.origin
        receiver.rightMouseDown(with: try event(.rightMouseDown, at: CGPoint(x: 50, y: 50), in: window))
        receiver.rightMouseDragged(with: try event(.rightMouseDragged, at: CGPoint(x: 85, y: 70), in: window))
        #expect(window.frame.origin == CGPoint(x: start.x + 35, y: start.y + 20))
        receiver.rightMouseUp(with: try event(.rightMouseUp, at: CGPoint(x: 50, y: 50), in: window))
        #expect(try store.load().windowPosition == WindowPosition(x: start.x + 35, y: start.y + 20))
    }

    @Test func launcherFacesAreHiddenUntilHoverAndHiddenAgainOnExit() throws {
        let (view, _, _, _, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let front = try #require(view.cube.findEntity(named: "front"))
        #expect(front.components[OpacityComponent.self]?.opacity == 0)
        view.setHovered(true)
        #expect(front.components[OpacityComponent.self]?.opacity == 1)
        view.setHovered(false)
        #expect(front.components[OpacityComponent.self]?.opacity == 0)
    }

    @Test func nativeHitTestingRoutesPointerEventsToTheCubeInputHandler() throws {
        let (view, _, _, _, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let receiver = view.hitTest(CGPoint(x: 82, y: 82))
        let routesToHandler = receiver === view
        #expect(routesToHandler)
    }

    private func fixture() throws -> (CubeView, NSPanel, AppModel, ConfigurationStore, URL) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        let model = AppModel(store: store)
        let view = CubeView(model: model)
        let screen = try #require(NSScreen.main?.visibleFrame)
        let window = NSPanel(contentRect: CGRect(x: screen.minX + 100, y: screen.minY + 100, width: 164, height: 164), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = view
        return (view, window, model, store, directory)
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    @Test func rightDragMovesAndPersistsWithoutOpeningEditor() throws {
        let (view, window, model, store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = window.frame.origin
        var editorRequests = 0
        view.editRequested = { editorRequests += 1 }
        view.rightMouseDown(with: try event(.rightMouseDown, at: CGPoint(x: 50, y: 50), in: window))
        #expect(editorRequests == 0)
        view.rightMouseDragged(with: try event(.rightMouseDragged, at: CGPoint(x: 95, y: 80), in: window))
        #expect(window.frame.origin == CGPoint(x: start.x + 45, y: start.y + 30))
        #expect(model.configuration.windowPosition == nil)
        #expect(view.containsCube(atWindowPoint: CGPoint(x: -200, y: -200)))
        view.rightMouseUp(with: try event(.rightMouseUp, at: CGPoint(x: 50, y: 50), in: window))
        #expect(editorRequests == 0)
        #expect(try store.load().windowPosition == WindowPosition(x: start.x + 45, y: start.y + 30))
        #expect(!view.containsCube(atWindowPoint: CGPoint(x: -200, y: -200)))
    }

    @Test func rightClickOpensEditorOnlyAfterRelease() throws {
        let (view, window, model, _, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var editorRequests = 0
        view.editRequested = { editorRequests += 1 }
        view.rightMouseDown(with: try event(.rightMouseDown, at: CGPoint(x: 50, y: 50), in: window))
        #expect(editorRequests == 0)
        view.rightMouseUp(with: try event(.rightMouseUp, at: CGPoint(x: 50, y: 50), in: window))
        #expect(editorRequests == 1)
        #expect(model.configuration.windowPosition == nil)
    }

    @Test func leftDragDoesNotRotateOrMoveTheCube() throws {
        let (view, window, model, _, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rotation = view.cube.orientation
        let origin = window.frame.origin
        view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 50, y: 50), in: window))
        view.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 100, y: 50), in: window))
        #expect(abs(simd_dot(rotation.vector, view.cube.orientation.vector)) > 0.9999)
        view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 100, y: 50), in: window))
        #expect(window.frame.origin == origin)
        #expect(model.configuration.windowPosition == nil)
    }
}
