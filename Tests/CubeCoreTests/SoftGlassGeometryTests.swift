import Testing
import simd
@testable import CubeCore

struct SoftGlassGeometryTests {
    @Test func bodyIsRoundedAtEdgesAndCornersAndFitsTheExistingInteractionEnvelope() {
        let body = SoftGlassGeometry()
        #expect(body.positions.count == body.normals.count)
        #expect(body.positions.count == body.textureCoordinates.count)
        #expect(!body.positions.isEmpty)
        // The quartic surface intersects its xy diagonal at pow(1/2, 1/4)/2.
        #expect(body.positions.contains { simd_distance($0, [0.42044821, 0.42044821, 0]) < 0.00001 })
        for point in body.positions {
            #expect(simd_abs(point).max() <= 0.500001)
            #expect(simd_length(point) < 0.67, "The body must not reach sharp cube corners")
            #expect(abs(pow(abs(point.x / 0.5), 4) + pow(abs(point.y / 0.5), 4) + pow(abs(point.z / 0.5), 4) - 1) < 0.00001)
        }
    }

    @Test func shellIsClosedAndTrianglesFaceOutwardWithoutNormalSeams() {
        let body = SoftGlassGeometry()
        var uses: [Edge: Int] = [:]
        for offset in stride(from: 0, to: body.indices.count, by: 3) {
            let ids = (0..<3).map { Int(body.indices[offset + $0]) }
            let a = body.positions[ids[0]], b = body.positions[ids[1]], c = body.positions[ids[2]]
            let cross = simd_cross(b - a, c - a)
            #expect(simd_length(cross) > 0.00000001)
            #expect(simd_dot(cross, body.normals[ids[0]] + body.normals[ids[1]] + body.normals[ids[2]]) > 0)
            for index in 0..<3 {
                let first = ids[index], second = ids[(index + 1) % 3]
                uses[Edge(first, second), default: 0] += 1
                #expect(simd_dot(body.normals[first], body.normals[second]) > 0.96)
            }
        }
        #expect(uses.values.allSatisfy { $0 == 2 }, "There must be no six-face openings or UV seam cracks")
        #expect(body.positions.count - uses.count + body.indices.count / 3 == 2)
        for (normal, uv) in zip(body.normals, body.textureCoordinates) {
            #expect(abs(simd_length(normal) - 1) < 0.00001)
            #expect(uv.min() >= 0 && uv.max() <= 1)
        }
    }

    private struct Edge: Hashable {
        let first: Int
        let second: Int
        init(_ a: Int, _ b: Int) { first = min(a, b); second = max(a, b) }
    }
}
