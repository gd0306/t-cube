import AppKit
import RealityKit
import CubeCore
import Testing
import simd
@testable import TCube

@MainActor
@Suite(.serialized)
struct SlimeInteractionTests {
    @Test func nativeMouseMotionBendsTheShellAndExitRestoresItWithoutMovingIcons() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("configuration.json")))
        let view = CubeView(model: model)
        let surface = CubeSurfaceView(cubeView: view)
        let window = NSPanel(contentRect: NSRect(x: 160, y: 160, width: 300, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.contentView = surface
        window.orderFrontRegardless()
        let shell = try #require(view.cube.findEntity(named: "glass-shell") as? ModelEntity)
        let initial = try positions(of: shell)
        let frame = window.frame
        let pose = view.cube.orientation
        let front = try #require(view.cube.findEntity(named: "front") as? ModelEntity)
        let icons = try positions(of: front)
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 165, y: 160), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
        surface.input.mouseMoved(with: event)
        for _ in 0..<20 { view.advanceAnimations(deltaTime: 1.0 / 30, reducedMotion: false) }
        let bent = try positions(of: shell)
        #expect(zip(initial, bent).contains { simd_distance($0, $1) > 0.04 })
        #expect(try positions(of: front) == icons)
        #expect(view.cube.orientation == pose)
        #expect(window.frame == frame)
        // A wheel notch rotates under a stationary pointer. The new visible
        // patch must respond without requiring another mouse-moved event.
        view.rotate(with: [0, 1], precise: false, inverted: false)
        let ray = try #require(view.ray(through: NSPoint(x: 165, y: 160)))
        let contact = try #require(CubeFacePicking.surfacePoint(origin: view.cube.convert(position: ray.origin, from: nil),
                                                             direction: view.cube.convert(direction: ray.direction, from: nil)))
        let closest = try #require(initial.indices.min { simd_distance(initial[$0], contact) < simd_distance(initial[$1], contact) })
        for _ in 0..<40 { view.advanceAnimations(deltaTime: 1.0 / 30, reducedMotion: false) }
        let rotated = try positions(of: shell)
        #expect(simd_distance(rotated[closest], initial[closest]) > 0.04)
        surface.input.mouseExited(with: event)
        for _ in 0..<120 { view.advanceAnimations(deltaTime: 1.0 / 30, reducedMotion: false) }
        let restored = try positions(of: shell)
        #expect(zip(initial, restored).allSatisfy { simd_distance($0, $1) < 0.0001 })
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("configuration.json").path))
    }

    private func positions(of entity: ModelEntity) throws -> [SIMD3<Float>] {
        let mesh = try #require(entity.model?.mesh)
        if let lowLevel = mesh.lowLevelMesh {
            var result: [SIMD3<Float>] = []
            lowLevel.withUnsafeBytes(bufferIndex: 0) { bytes in
                let stride = lowLevel.descriptor.vertexLayouts[0].bufferStride
                for index in 0..<lowLevel.vertexCapacity {
                    result.append(bytes.load(fromByteOffset: index * stride, as: SIMD3<Float>.self))
                }
            }
            return result
        }
        return mesh.contents.models.flatMap { $0.parts.flatMap { Array($0.positions) } }
    }
}
