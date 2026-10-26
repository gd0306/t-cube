import simd

/// The fillets of a rounded box, with its six flat face interiors omitted.
public struct RoundedCubeFrameGeometry: Sendable {
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let textureCoordinates: [SIMD2<Float>]
    public let indices: [UInt32]

    public init(halfExtent: Float = 0.5, cornerRadius: Float = 0.045, segments: Int = 16) {
        precondition(halfExtent.isFinite && halfExtent > 0)
        precondition(cornerRadius.isFinite && cornerRadius > 0 && cornerRadius < halfExtent)
        precondition(segments >= 1)

        let coreExtent = halfExtent - cornerRadius
        // Exact endpoint values make all three parameterizations share the same tangent vertices.
        let angles: [(cosine: Float, sine: Float)] = (0...segments).map { step in
            if step == 0 { return (1, 0) }
            if step == segments { return (0, 1) }
            let angle = Double(step) * .pi / (2 * Double(segments))
            return (Float(cos(angle)), Float(sin(angle)))
        }
        var builder = FrameMeshBuilder(halfExtent: halfExtent)

        // Each edge is a quarter cylinder. Its two longitudinal ends meet the corner octants.
        for axis in 0..<3 {
            let perpendicularAxes = (0..<3).filter { $0 != axis }
            for firstSign: Float in [-1, 1] {
                for secondSign: Float in [-1, 1] {
                    var strip: [(UInt32, UInt32)] = []
                    for angle in angles {
                        var normal = SIMD3<Float>.zero
                        normal[perpendicularAxes[0]] = firstSign * angle.cosine
                        normal[perpendicularAxes[1]] = secondSign * angle.sine
                        var center = SIMD3<Float>.zero
                        center[perpendicularAxes[0]] = firstSign * coreExtent
                        center[perpendicularAxes[1]] = secondSign * coreExtent
                        var negative = center + cornerRadius * normal
                        var positive = negative
                        negative[axis] = -coreExtent
                        positive[axis] = coreExtent
                        strip.append((builder.vertex(negative, normal: normal), builder.vertex(positive, normal: normal)))
                    }
                    for step in 0..<segments {
                        let previous = strip[step]
                        let next = strip[step + 1]
                        builder.triangle(previous.0, previous.1, next.1)
                        builder.triangle(previous.0, next.1, next.0)
                    }
                }
            }
        }

        // Octant boundary curves use the same sine/cosine samples as the adjacent edge strips.
        for xSign: Float in [-1, 1] {
            for ySign: Float in [-1, 1] {
                for zSign: Float in [-1, 1] {
                    let signs = SIMD3(xSign, ySign, zSign)
                    let center = coreExtent * signs
                    var patch: [[UInt32]] = []
                    for theta in angles {
                        var row: [UInt32] = []
                        for phi in angles {
                            let normal = signs * SIMD3(theta.cosine * phi.cosine, theta.sine * phi.cosine, phi.sine)
                            row.append(builder.vertex(center + cornerRadius * normal, normal: normal))
                        }
                        patch.append(row)
                    }
                    for theta in 0..<segments {
                        for phi in 0..<segments {
                            builder.triangle(patch[theta][phi], patch[theta + 1][phi], patch[theta + 1][phi + 1])
                            builder.triangle(patch[theta][phi], patch[theta + 1][phi + 1], patch[theta][phi + 1])
                        }
                    }
                }
            }
        }

        positions = builder.positions
        normals = builder.normals
        textureCoordinates = builder.textureCoordinates
        indices = builder.indices
    }
}

private struct FrameMeshBuilder {
    let halfExtent: Float
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var textureCoordinates: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    private var vertices: [VertexKey: UInt32] = [:]

    init(halfExtent: Float) {
        self.halfExtent = halfExtent
    }

    mutating func vertex(_ position: SIMD3<Float>, normal: SIMD3<Float>) -> UInt32 {
        let key = VertexKey(position: quantized(position), normal: quantized(normal))
        if let existing = vertices[key] { return existing }
        let index = UInt32(positions.count)
        vertices[key] = index
        positions.append(position)
        normals.append(normal)
        // A single world-space projection keeps the material continuous across every patch join.
        textureCoordinates.append(SIMD2(
            position.x / (2 * halfExtent) + 0.5,
            (position.y + 0.35 * position.z + 1.35 * halfExtent) / (2.7 * halfExtent)
        ))
        return index
    }

    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        // All samples at an octant pole weld to one vertex; omit the collapsed triangles there.
        guard a != b, b != c, c != a else { return }
        let cross = simd_cross(positions[Int(b)] - positions[Int(a)], positions[Int(c)] - positions[Int(a)])
        let outward = normals[Int(a)] + normals[Int(b)] + normals[Int(c)]
        let orientation = simd_dot(cross, outward)
        guard orientation != 0 else { return }
        indices.append(contentsOf: orientation > 0 ? [a, b, c] : [a, c, b])
    }

    private func quantized(_ value: SIMD3<Float>) -> SIMD3<Int64> {
        SIMD3(
            Int64((Double(value.x) * 1_000_000).rounded()),
            Int64((Double(value.y) * 1_000_000).rounded()),
            Int64((Double(value.z) * 1_000_000).rounded())
        )
    }

    private struct VertexKey: Hashable {
        let position: SIMD3<Int64>
        let normal: SIMD3<Int64>
    }
}
