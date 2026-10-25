import Testing
import simd
@testable import CubeCore

struct CubeScrollMotionTests {
    @Test func naturalTrackpadRightAndUpMoveTheFrontSurfaceWithTheFingers() {
        let start = CubeRotation.snapped(to: .front)
        let right = CubeScrollMotion.rotated(from: start, delta: [30, 0], precise: true, inverted: true)
        let up = CubeScrollMotion.rotated(from: start, delta: [0, -30], precise: true, inverted: true)
        let rightNormal = (CubeRotation.displayTilt.inverse * right).act([0, 0, 1])
        let upNormal = (CubeRotation.displayTilt.inverse * up).act([0, 0, 1])
        #expect(rightNormal.x > 0.5)
        #expect(abs(rightNormal.y) < 0.001)
        #expect(upNormal.y > 0.5)
        #expect(abs(upNormal.x) < 0.001)
    }

    @Test func naturalScrollPreferenceDoesNotReverseThePhysicalGesture() {
        let start = CubeRotation.snapped(to: .front)
        let natural = CubeScrollMotion.rotated(from: start, delta: [20, -30], precise: true, inverted: true)
        let traditional = CubeScrollMotion.rotated(from: start, delta: [-20, 30], precise: true, inverted: false)
        #expect(abs(simd_dot(natural.vector, traditional.vector)) > 0.9999)
    }

    @Test func modestHorizontalAndVerticalSwipesReachAdjacentFacesEqually() {
        let start = CubeRotation.snapped(to: .front)
        let fixtures: [(SIMD2<Float>, CubeFace)] = [([45, 0], .left), ([-45, 0], .right), ([0, -45], .bottom), ([0, 45], .top)]
        for (delta, expected) in fixtures {
            let result = CubeScrollMotion.rotated(from: start, delta: delta, precise: true, inverted: true)
            #expect(CubeScrollMotion.targetFace(for: result) == expected)
        }
    }

    @Test func invalidMotionDoesNotChangeOrientation() {
        let start = CubeRotation.snapped(to: .right)
        let invalid = CubeScrollMotion.rotated(from: start, delta: [.nan, 1], precise: true, inverted: true)
        #expect(abs(simd_dot(start.vector, invalid.vector)) > 0.9999)
    }
}
