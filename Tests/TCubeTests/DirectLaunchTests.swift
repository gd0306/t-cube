import AppKit
import CubeCore
import RealityKit
import Testing
import simd
@testable import TCube

@MainActor
@Suite(.serialized)
struct DirectLaunchTests {
    @Test func directClicksLaunchEverySlotOnEveryRotatedFace() async throws {
        let (view, window, _, directory) = try fixture()
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        try await Task.sleep(for: .milliseconds(150))
        var launched: [String] = []
        var expansions = 0
        view.launchRequested = { slot, face in launched.append("\(face.rawValue):\(slot)") }
        view.faceRequested = { _, _ in expansions += 1 }
        let centers: [SIMD2<Float>] = [[-0.18785156, 0.14273438], [0.18785156, 0.14273438], [-0.18785156, -0.16078125], [0.18785156, -0.16078125]]
        var expected: [String] = []
        for face in CubeFace.allCases {
            view.cube.orientation = CubeRotation.snapped(to: face)
            for (slot, center) in centers.enumerated() {
                let point = try projected(center, face: face, view: view)
                try click(point, view: view, window: window)
                expected.append("\(face.rawValue):\(slot)")
            }
        }
        #expect(launched == expected)
        #expect(expansions == 0)
    }

    @Test func emptySlotsAndBlankAreasDoNothingAndModeChangesApplyImmediately() async throws {
        let (view, window, model, directory) = try fixture()
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        model.change { try $0.remove(from: .front, slot: 1) }
        view.refreshTextures()
        try await Task.sleep(for: .milliseconds(150))
        var launches = 0
        var expansions = 0
        view.launchRequested = { _, _ in launches += 1 }
        view.faceRequested = { _, _ in expansions += 1 }
        for center: SIMD2<Float> in [[0, 0], [0.18785156, 0.14273438], [-0.31, 0.14273438]] {
            try click(projected(center, face: .front, view: view), view: view, window: window)
        }
        #expect(launches == 0 && expansions == 0)
        model.change { $0.expandsFacesOnClick = true }
        try click(projected([0, 0], face: .front, view: view), view: view, window: window)
        #expect(expansions == 1 && launches == 0)
    }

    @Test func draggingAndControlMoveOnlyGesturesDoNotLaunchIcons() async throws {
        let (view, window, _, directory) = try fixture()
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        try await Task.sleep(for: .milliseconds(150))
        var launches = 0
        view.launchRequested = { _, _ in launches += 1 }
        let point = try projected([-0.18785156, 0.14273438], face: .front, view: view)
        let start = window.frame.origin
        view.mouseDown(with: try event(.leftMouseDown, at: point, window: window))
        view.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: point.x + 30, y: point.y + 20), window: window))
        view.mouseUp(with: try event(.leftMouseUp, at: point, window: window))
        #expect(window.frame.origin == CGPoint(x: start.x + 30, y: start.y + 20))
        view.beginPrimaryDrag(atScreenPoint: window.convertPoint(toScreen: point), moveOnly: true)
        view.mouseUp(with: try event(.leftMouseUp, at: point, window: window))
        #expect(launches == 0)
    }

    private func fixture() throws -> (CubeView, NSPanel, AppModel, URL) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("settings.json")))
        model.change {
            $0.expandsFacesOnClick = false
            for face in CubeFace.allCases {
                for index in 0..<4 {
                    try $0.add(LauncherItem(url: URL(fileURLWithPath: "/Applications/test-\(index).app"), name: "App \(index)", kind: .application), to: face)
                }
            }
        }
        let view = CubeView(model: model)
        view.setHovered(true)
        let screen = try #require(NSScreen.main?.visibleFrame)
        let window = NSPanel(contentRect: CGRect(x: screen.minX + 200, y: screen.minY + 200, width: 320, height: 320), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        return (view, window, model, directory)
    }

    private func projected(_ local: SIMD2<Float>, face: CubeFace, view: CubeView) throws -> CGPoint {
        let world = view.cube.convert(position: face.orientation.act([local.x, local.y, 0.501]), to: nil)
        let point = try #require(view.project(world))
        return view.convert(point, to: nil)
    }

    private func click(_ point: CGPoint, view: CubeView, window: NSWindow) throws {
        view.mouseDown(with: try event(.leftMouseDown, at: point, window: window))
        view.mouseUp(with: try event(.leftMouseUp, at: point, window: window))
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
}
