import simd

/// A closed quartic superellipsoid: the silhouette bends continuously instead of
/// meeting at twelve edges. Icon decals use the same surface projection.
public struct SoftGlassGeometry: Sendable {
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let textureCoordinates: [SIMD2<Float>]
    public let indices: [UInt32]

    public init(halfExtent: Float = 0.5, segments: Int = 48) {
        precondition(halfExtent.isFinite && halfExtent > 0)
        precondition(segments >= 8)
        let columns = 2 * segments
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var textureCoordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        func vertex(_ direction: SIMD3<Float>) {
            let position = SoftGlassSurface.project(direction, halfExtent: halfExtent)
            let point = position / halfExtent
            positions.append(position)
            normals.append(SoftGlassSurface.normal(at: point))
            // One continuous spatial projection avoids per-face reflection seams.
            textureCoordinates.append(SIMD2((point.x + 0.35 * point.z) / 2.7 + 0.5,
                                           (point.y + 0.25 * point.z) / 2.5 + 0.5))
        }
        vertex([0, 1, 0])
        for row in 1..<segments {
            let theta = Float(row) * .pi / Float(segments)
            for column in 0..<columns {
                let phi = Float(column) * 2 * .pi / Float(columns)
                vertex([sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)])
            }
        }
        vertex([0, -1, 0])
        let bottom = UInt32(positions.count - 1)
        func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
            let outward = normals[Int(a)] + normals[Int(b)] + normals[Int(c)]
            let cross = simd_cross(positions[Int(b)] - positions[Int(a)], positions[Int(c)] - positions[Int(a)])
            indices.append(contentsOf: simd_dot(cross, outward) > 0 ? [a, b, c] : [a, c, b])
        }
        for column in 0..<columns {
            let next = (column + 1) % columns
            triangle(0, UInt32(1 + column), UInt32(1 + next))
            for row in 0..<(segments - 2) {
                let a = UInt32(1 + row * columns + column)
                let b = UInt32(1 + row * columns + next)
                let c = UInt32(1 + (row + 1) * columns + column)
                let d = UInt32(1 + (row + 1) * columns + next)
                triangle(a, b, d)
                triangle(a, d, c)
            }
            let last = 1 + (segments - 2) * columns
            triangle(bottom, UInt32(last + next), UInt32(last + column))
        }
        self.positions = positions
        self.normals = normals
        self.textureCoordinates = textureCoordinates
        self.indices = indices
    }
}

enum SoftGlassSurface {
    static func project(_ direction: SIMD3<Float>, halfExtent: Float = 0.5) -> SIMD3<Float> {
        let squared = direction * direction
        let denominator = pow(simd_dot(squared, squared), Float(0.25))
        return halfExtent * direction / denominator
    }

    static func normal(at point: SIMD3<Float>) -> SIMD3<Float> {
        simd_normalize(point * point * point)
    }
}
