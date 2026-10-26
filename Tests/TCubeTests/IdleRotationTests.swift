import AppKit
import CubeCore
import RealityKit
import Testing
import simd
@testable import TCube

@MainActor
@Suite(.serialized)
struct IdleRotationTests {
    @Test func disabledReducedMotionHiddenAndSecondaryDragStatesKeepThePose() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("configuration.json")))
        let view = CubeView(model: model)
        let window = NSPanel(contentRect: NSRect(x: 140, y: 140, width: 164, height: 164), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.contentView = view
        window.orderFrontRegardless()
        let initial = view.cube.orientation
        for _ in 0..<60 { view.advanceAnimations(deltaTime: 1.0 / 30, reducedMotion: true) }
        #expect(simd_length(view.cube.orientation.vector - initial.vector) < 0.00001)
        model.change { $0.autoRotatesWhenIdle = false }
        for _ in 0..<60 { view.advanceAnimations(deltaTime: 1.0 / 30, reducedMotion: false) }
        #expect(simd_length(view.cube.orientation.vector - initial.vector) < 0.00001)
        model.change { $0.autoRotatesWhenIdle = true }
        view.beginSecondaryDrag(atScreenPoint: window.frame.origin)
        for _ in 0..<60 { view.advanceAnimations(deltaTime: 1.0 / 30, reducedMotion: false) }
        #expect(simd_length(view.cube.orientation.vector - initial.vector) < 0.00001)
        view.cancelRightDrag()
        window.orderOut(nil)
        view.advanceAnimations(deltaTime: 600, reducedMotion: false)
        #expect(simd_length(view.cube.orientation.vector - initial.vector) < 0.00001)
        window.orderFrontRegardless()
        view.advanceAnimations(deltaTime: 600, reducedMotion: false)
        let resumed = view.cube.orientation
        #expect(simd_length(resumed.vector - initial.vector) > 0.0001)
        #expect(simd_length(resumed.vector - initial.vector) < 0.01, "Showing the cube must not catch up on hidden time")
    }

    @Test func sceneRotatesAtRestAndNativeHoverFreezesTheCurrentPose() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("configuration.json")))
        let view = CubeView(model: model)
        let surface = CubeSurfaceView(cubeView: view)
        let window = NSPanel(contentRect: NSRect(x: 140, y: 140, width: 164, height: 164), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.contentView = surface
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(300))
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let initial = view.cube.orientation
        try await Task.sleep(for: .milliseconds(800))
        if reducedMotion {
            #expect(simd_length(initial.vector - view.cube.orientation.vector) < 0.00001)
        } else {
            #expect(simd_length(initial.vector - view.cube.orientation.vector) > 0.005, "The actual scene must rotate while idle")
        }

        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 82, y: 82), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
        surface.input.mouseEntered(with: event)
        let stopped = view.cube.orientation
        try await Task.sleep(for: .milliseconds(350))
        #expect(simd_length(stopped.vector - view.cube.orientation.vector) < 0.00001)
        view.rotate(with: [18, -9], precise: true, inverted: true)
        let manuallyRotated = view.cube.orientation
        try await Task.sleep(for: .milliseconds(350))
        #expect(simd_length(manuallyRotated.vector - view.cube.orientation.vector) < 0.00001)

        surface.input.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(800))
        if reducedMotion {
            #expect(simd_length(manuallyRotated.vector - view.cube.orientation.vector) < 0.00001)
        } else {
            #expect(simd_length(manuallyRotated.vector - view.cube.orientation.vector) > 0.005)
        }
        let frame = window.frame
        view.beginPrimaryDrag(atScreenPoint: frame.origin, moveOnly: true)
        let dragging = view.cube.orientation
        try await Task.sleep(for: .milliseconds(350))
        #expect(simd_length(dragging.vector - view.cube.orientation.vector) < 0.00001)
        view.cancelPrimaryDrag()
        #expect(window.frame == frame)
        #expect(model.configuration.windowPosition == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("configuration.json").path))
    }
}
