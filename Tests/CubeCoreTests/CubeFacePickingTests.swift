import Testing
import simd
@testable import CubeCore

struct CubeFacePickingTests {
    @Test func eachFaceCanBeSelectedIncludingItsUntexturedRim() {
        let cases: [(SIMD3<Float>, SIMD3<Float>, CubeFace)] = [
            ([0.48, 0.48, 3], [0, 0, -1], .front),
            ([3, 0.48, 0.48], [-1, 0, 0], .right),
            ([0.48, 0.48, -3], [0, 0, 1], .back),
            ([-3, 0.48, 0.48], [1, 0, 0], .left),
            ([0.48, 3, 0.48], [0, -1, 0], .top),
            ([0.48, -3, 0.48], [0, 1, 0], .bottom)
        ]
        for (origin, direction, face) in cases {
            #expect(CubeFacePicking.face(origin: origin, direction: direction) == face)
        }
    }

    @Test func missesAndInvalidRaysDoNotSelectAFace() {
        #expect(CubeFacePicking.face(origin: [1, 0, 3], direction: [0, 0, -1]) == nil)
        #expect(CubeFacePicking.face(origin: [0, 0, 3], direction: [0, 0, 1]) == nil)
        #expect(CubeFacePicking.face(origin: [0, 0, 3], direction: .zero) == nil)
        #expect(CubeFacePicking.face(origin: [.nan, 0, 3], direction: [0, 0, -1]) == nil)
    }

    @Test func obliqueRayChoosesTheFirstVisibleSurface() {
        // At t = 5/6 the front/right plane is reached at the other coordinate 1/3.
        #expect(CubeFacePicking.face(origin: [2, 0, 3], direction: [-2, 0, -3]) == .front)
        #expect(CubeFacePicking.face(origin: [3, 0, 2], direction: [-3, 0, -2]) == .right)
    }
}
