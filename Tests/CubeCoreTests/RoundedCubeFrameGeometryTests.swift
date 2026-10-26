import Testing
import simd
@testable import CubeCore

struct RoundedCubeFrameGeometryTests {
    @Test func filletsStayWithinTheCubeAndLeaveFaceInteriorsEmpty() {
        let mesh = RoundedCubeFrameGeometry()
        #expect(!mesh.positions.isEmpty)
        #expect(mesh.positions.count == mesh.normals.count)
        #expect(mesh.positions.count == mesh.textureCoordinates.count)
        #expect(!mesh.indices.isEmpty)
        #expect(mesh.indices.count.isMultiple(of: 3))

        for (position, normal) in zip(mesh.positions, mesh.normals) {
            let absolute = simd_abs(position)
            #expect(absolute.max() <= 0.500001)
            #expect((0..<3).filter { absolute[$0] >= 0.454999 }.count >= 2)
            #expect(simd_length(position - simd_clamp(position, SIMD3(repeating: -0.455), SIMD3(repeating: 0.455))) > 0.044999)
            #expect(abs(simd_length(normal) - 1) < 0.00001)
            // A sharp cube corner is sqrt(3)/2 from the origin; the rounded frame never reaches it.
            #expect(simd_length(position) < 0.86)
        }
    }

    @Test func trianglesHaveAreaAndFaceTheirSmoothNormals() {
        let mesh = RoundedCubeFrameGeometry()
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ids = (0..<3).map { Int(mesh.indices[offset + $0]) }
            #expect(ids.allSatisfy { mesh.positions.indices.contains($0) })
            let a = mesh.positions[ids[0]]
            let b = mesh.positions[ids[1]]
            let c = mesh.positions[ids[2]]
            let cross = simd_cross(b - a, c - a)
            #expect(simd_length(cross) > 0.00000001)
            #expect(simd_dot(cross, ids.reduce(SIMD3<Float>.zero) { $0 + mesh.normals[$1] }) > 0)
        }
    }

    @Test func weldedSurfaceIsConnectedWithExactlySixOpenFaceHoles() {
        let mesh = RoundedCubeFrameGeometry()
        var adjacency = Array(repeating: Set<Int>(), count: mesh.positions.count)
        var edgeUses: [Edge: Int] = [:]
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ids = (0..<3).map { Int(mesh.indices[offset + $0]) }
            for i in 0..<3 {
                let a = ids[i]
                let b = ids[(i + 1) % 3]
                adjacency[a].insert(b)
                adjacency[b].insert(a)
                edgeUses[Edge(a, b), default: 0] += 1
            }
        }
        #expect(!adjacency.isEmpty)
        guard !adjacency.isEmpty else { return }
        #expect(reachable(from: 0, in: adjacency).count == mesh.positions.count)
        #expect(edgeUses.values.allSatisfy { $0 == 1 || $0 == 2 })

        var boundary = Array(repeating: Set<Int>(), count: mesh.positions.count)
        for (edge, count) in edgeUses where count == 1 {
            boundary[edge.a].insert(edge.b)
            boundary[edge.b].insert(edge.a)
        }
        #expect(boundary.filter { !$0.isEmpty }.allSatisfy { $0.count == 2 })
        var remaining = Set(boundary.indices.filter { !boundary[$0].isEmpty })
        var holes: [Set<Int>] = []
        while let start = remaining.first {
            let loop = reachable(from: start, in: boundary)
            holes.append(loop)
            remaining.subtract(loop)
        }
        #expect(holes.count == 6)
        // Each hole lies in one of the six outer face planes, with no triangulated face cap.
        var facePlanes = Set<Int>()
        for hole in holes {
            let planes = (0..<6).filter { plane in
                hole.allSatisfy { abs(mesh.positions[$0][plane / 2] - (plane.isMultiple(of: 2) ? 0.5 : -0.5)) < 0.000001 }
            }
            #expect(planes.count == 1)
            facePlanes.formUnion(planes)
        }
        #expect(facePlanes.count == 6)
        #expect(mesh.positions.count - edgeUses.count + mesh.indices.count / 3 == -4)
    }

    @Test func cornersHaveCurvedNormalsAndGlobalContinuousTextureCoordinates() {
        let mesh = RoundedCubeFrameGeometry()
        var curvedOctants = Set<Int>()
        for index in mesh.positions.indices {
            let p = mesh.positions[index]
            let n = mesh.normals[index]
            if simd_abs(n).min() > 0.1 {
                curvedOctants.insert((p.x > 0 ? 1 : 0) | (p.y > 0 ? 2 : 0) | (p.z > 0 ? 4 : 0))
            }
            let uv = mesh.textureCoordinates[index]
            #expect(abs(uv.x - (p.x + 0.5)) < 0.000001)
            let expectedV: Float = (p.y + 0.35 * p.z + 0.675) / 1.35
            #expect(abs(uv.y - expectedV) < 0.000001)
            #expect(uv.min() >= -0.000001 && uv.max() <= 1.000001)
        }
        #expect(curvedOctants.count == 8)
    }

    @Test func customDimensionsProduceTheHandCalculatedFortyFiveDegreeFillet() {
        let mesh = RoundedCubeFrameGeometry(halfExtent: 1, cornerRadius: 0.2, segments: 4)
        let expected = SIMD3<Float>(0.94142136, 0.94142136, 0.8)
        let index = mesh.positions.firstIndex { simd_distance($0, expected) < 0.000001 }
        #expect(index != nil)
        if let index {
            #expect(simd_distance(mesh.normals[index], SIMD3<Float>(0.70710677, 0.70710677, 0)) < 0.000001)
        }
        #expect(mesh.positions.allSatisfy { simd_abs($0).max() <= 1.000001 })
    }

    private struct Edge: Hashable {
        let a: Int
        let b: Int

        init(_ first: Int, _ second: Int) {
            a = min(first, second)
            b = max(first, second)
        }
    }

    private func reachable(from start: Int, in adjacency: [Set<Int>]) -> Set<Int> {
        var visited: Set<Int> = [start]
        var pending = [start]
        while let current = pending.popLast() {
            for neighbor in adjacency[current] where visited.insert(neighbor).inserted {
                pending.append(neighbor)
            }
        }
        return visited
    }
}
