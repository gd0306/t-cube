import Testing
import simd
@testable import CubeCore

struct CubeFacePickingTests {
    @Test func eachCurvedGroupCanBeSelectedIncludingItsUntexturedRim() {
        let cases: [(SIMD3<Float>, SIMD3<Float>, CubeFace)] = [
            ([0.28, 0.28, 3], [0, 0, -1], .front),
            ([3, 0.28, 0.28], [-1, 0, 0], .right),
            ([0.28, 0.28, -3], [0, 0, 1], .back),
            ([-3, 0.28, 0.28], [1, 0, 0], .left),
            ([0.28, 3, 0.28], [0, -1, 0], .top),
            ([0.28, -3, 0.28], [0, 1, 0], .bottom)
        ]
        for (origin, direction, face) in cases {
            #expect(CubeFacePicking.face(origin: origin, direction: direction) == face)
        }
    }

    @Test func missesAndInvalidRaysDoNotSelectAFace() {
        #expect(CubeFacePicking.face(origin: [1, 0, 3], direction: [0, 0, -1]) == nil)
        #expect(CubeFacePicking.face(origin: [0.48, 0.48, 3], direction: [0, 0, -1]) == nil)
        #expect(CubeFacePicking.face(origin: [0, 0, 3], direction: [0, 0, 1]) == nil)
        #expect(CubeFacePicking.face(origin: [0, 0, 3], direction: .zero) == nil)
        #expect(CubeFacePicking.face(origin: [.nan, 0, 3], direction: [0, 0, -1]) == nil)
    }

    @Test func obliqueRayChoosesTheFirstVisibleSurface() {
        // The first curved surface belongs to the group with the dominant coordinate.
        #expect(CubeFacePicking.face(origin: [2, 0, 3], direction: [-2, 0, -3]) == .front)
        #expect(CubeFacePicking.face(origin: [3, 0, 2], direction: [-3, 0, -2]) == .right)
    }
}
