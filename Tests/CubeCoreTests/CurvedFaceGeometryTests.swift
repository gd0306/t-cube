import Testing
import simd
@testable import CubeCore

struct CurvedFaceGeometryTests {
    @Test func faceCurvatureIsShallowWhileItsCornersStayRounded() {
        let patch = CurvedFaceGeometry()
        let depthRange = (patch.positions.map(\.z).max() ?? 0) - (patch.positions.map(\.z).min() ?? 0)
        #expect(depthRange > 0.04 && depthRange < 0.09, "Each group should lie on a gently curved face, rather than an inflated dome")
    }

    @Test func iconPatchUsesTheSameCurvedShellWithOnlyADecalOffset() {
        let patch = CurvedFaceGeometry()
        #expect(patch.positions.count == patch.normals.count)
        #expect(patch.positions.count == patch.textureCoordinates.count)
        #expect(simd_distance(FaceLayout.surfacePoint(at: .zero), [0, 0, 0.5015]) < 0.000001)
        #expect(simd_distance(FaceLayout.surfacePoint(at: [-0.101, 0.14273438]), [-0.10080372, 0.14247441, 0.50046665]) < 0.000001)
        for point in patch.positions {
            let implicit = pow(abs(point.x), 4) + pow(abs(point.y), 4) + pow(abs(point.z), 4)
            #expect(implicit > 0.0625 && implicit < 0.0645, "The decal must hug the shell, including its outer corners")
        }
        let depths = patch.positions.map(\.z)
        #expect((depths.max() ?? 0) - (depths.min() ?? 0) > 0.04, "The icon patch must bend, rather than remain a flat plate")
    }

    @Test func everyCurvedIconAndItsMarginsCanBePickedFromObliqueAngles() {
        let points: [(SIMD2<Float>, Int?)] = [
            ([-0.18785156, 0.14273438], 0), ([0.18785156, 0.14273438], 1),
            ([-0.18785156, -0.16078125], 2), ([0.18785156, -0.16078125], 3),
            ([-0.101, 0.14273438], 0), ([0, 0], nil), ([-0.31, 0.14273438], nil)
        ]
        for face in CubeFace.allCases {
            for (local, slot) in points {
                let point = FaceLayout.surfacePoint(at: local)
                for eye: SIMD3<Float> in [[0, 0, 3], [2.5, 1.2, 3], [-2.5, -1.2, 3]] {
                    let origin = face.orientation.act(eye)
                    let target = face.orientation.act(point)
                    let hit = CubeFacePicking.icon(origin: origin, direction: target - origin)
                    #expect(hit?.slot == slot)
                    if slot != nil { #expect(hit?.face == face) }
                }
            }
        }
    }

    @Test func patchTrianglesFaceOutwardAndKeepTheImageUpright() {
        let patch = CurvedFaceGeometry()
        for index in patch.positions.indices {
            let point = patch.positions[index]
            let uv = patch.textureCoordinates[index]
            #expect(abs(simd_length(patch.normals[index]) - 1) < 0.00001)
            #expect(uv.min() >= 0 && uv.max() <= 1)
            #expect((uv.x - 0.5) * point.x >= -0.000001)
            #expect((uv.y - 0.5) * point.y >= -0.000001)
        }
        for offset in stride(from: 0, to: patch.indices.count, by: 3) {
            let ids = (0..<3).map { Int(patch.indices[offset + $0]) }
            let a = patch.positions[ids[0]], b = patch.positions[ids[1]], c = patch.positions[ids[2]]
            #expect(simd_dot(simd_cross(b - a, c - a), patch.normals[ids[0]]) > 0)
        }
    }
}
