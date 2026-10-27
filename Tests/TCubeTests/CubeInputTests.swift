import AppKit
import CubeCore
import Testing
import simd
import RealityKit
@testable import TCube

@MainActor
@Suite(.serialized)
struct CubeInputTests {
    @Test func repeatedClicksExpandImmediatelyWithoutOpeningSettings() async throws {
        let (view, window, _, _, directory) = try fixture()
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(150))
        var editorRequests = 0
        var faceRequests = 0
        view.editRequested = { editorRequests += 1 }
        view.faceRequested = { _, _ in faceRequests += 1 }
        let projected = try #require(view.project(view.cube.convert(position: CubeFace.front.normal * 0.501, to: nil)))
        let point = view.convert(projected, to: nil)
        view.mouseDown(with: try event(.leftMouseDown, at: point, in: window))
        view.mouseUp(with: try event(.leftMouseUp, at: point, in: window))
        #expect(faceRequests == 1)
        view.mouseDown(with: try event(.leftMouseDown, at: point, in: window, clickCount: 2))
        view.mouseUp(with: try event(.leftMouseUp, at: point, in: window, clickCount: 2))
        #expect(editorRequests == 0)
        #expect(faceRequests == 2)
    }

    @Test func clickExpandsTheSelectedFaceImmediatelyOnRelease() async throws {
        let (view, window, model, _, directory) = try fixture()
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(150))
        let world = view.cube.convert(position: CubeFace.front.normal * 0.501, to: nil)
        let projected = try #require(view.project(world))
        let point = view.convert(projected, to: nil)
        var expanded: [CubeFace] = []
        view.faceRequested = { face, _ in expanded.append(face) }
        view.mouseDown(with: try event(.leftMouseDown, at: point, in: window))
        #expect(expanded.isEmpty)
        view.mouseUp(with: try event(.leftMouseUp, at: point, in: window))
        #expect(expanded == [.front])
        #expect(model.selectedFace == .front)
        #expect(model.configuration.windowPosition == nil)
    }

    @Test func scrollPoseStaysExactlyWhereItStopped() async throws {
        let (view, _, _, _, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        view.rotate(with: [18, -9], precise: true, inverted: true)
        let stopped = view.cube.orientation
        try await Task.sleep(for: .milliseconds(650))
        #expect(abs(simd_dot(stopped.vector, view.cube.orientation.vector)) > 0.99999)
        let canonical = CubeRotation.snapped(to: CubeScrollMotion.targetFace(for: stopped))
        #expect(abs(simd_dot(stopped.vector, canonical.vector)) < 0.999)
    }

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
        receiver.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 50, y: 50), in: window))
        receiver.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 85, y: 70), in: window))
        #expect(window.frame.origin == CGPoint(x: start.x + 35, y: start.y + 20))
        receiver.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 50, y: 50), in: window))
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

    private func event(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow, clickCount: Int = 1) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: clickCount, pressure: 1))
    }

    @Test func rightDragRotatesWithoutMovingSavingOrOpeningEditor() throws {
        let (view, window, model, store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = window.frame
        let rotation = view.cube.orientation
        var editorRequests = 0
        view.editRequested = { editorRequests += 1 }
        view.rightMouseDown(with: try event(.rightMouseDown, at: CGPoint(x: 50, y: 50), in: window))
        view.rightMouseDragged(with: try event(.rightMouseDragged, at: CGPoint(x: 95, y: 80), in: window))
        #expect(window.frame == start)
        #expect(abs(simd_dot(rotation.vector, view.cube.orientation.vector)) < 0.999)
        #expect(view.containsCube(atWindowPoint: CGPoint(x: -200, y: -200)))
        view.rightMouseUp(with: try event(.rightMouseUp, at: CGPoint(x: 110, y: 90), in: window))
        let stopped = view.cube.orientation
        #expect(abs(simd_length(stopped.vector) - 1) < 0.00001)
        #expect(window.frame == start)
        #expect(editorRequests == 0)
        #expect(model.configuration.windowPosition == nil)
        #expect(try store.load().windowPosition == nil)
        #expect(!view.containsCube(atWindowPoint: CGPoint(x: -200, y: -200)))
        // A second drag starts from the last pose; zero displacement cannot reset it.
        view.rightMouseDown(with: try event(.rightMouseDown, at: CGPoint(x: 60, y: 60), in: window))
        view.rightMouseDragged(with: try event(.rightMouseDragged, at: CGPoint(x: 80, y: 60), in: window))
        view.rightMouseDragged(with: try event(.rightMouseDragged, at: CGPoint(x: 60, y: 60), in: window))
        #expect(abs(simd_dot(stopped.vector, view.cube.orientation.vector)) > 0.99999)
        view.cancelRightDrag()
        #expect(window.frame == start)
        #expect(editorRequests == 0)
        #expect(try store.load().windowPosition == nil)
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

    @Test func primaryButtonDragMovesAndPersistsWithoutRotatingOrOpeningAnything() throws {
        let (view, window, model, store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rotation = view.cube.orientation
        let origin = window.frame.origin
        var editorRequests = 0
        view.editRequested = { editorRequests += 1 }
        view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 50, y: 50), in: window))
        view.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 90, y: 75), in: window))
        #expect(abs(simd_dot(rotation.vector, view.cube.orientation.vector)) > 0.9999)
        #expect(window.frame.origin == CGPoint(x: origin.x + 40, y: origin.y + 25))
        #expect(model.configuration.windowPosition == nil)
        view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 50, y: 50), in: window))
        #expect(try store.load().windowPosition == WindowPosition(x: origin.x + 40, y: origin.y + 25))
        #expect(editorRequests == 0)
    }
}
