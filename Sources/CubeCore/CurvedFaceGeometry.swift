import simd

/// A subdivided icon texture, draped over the same surface as the glass body.
/// Drawing and ray picking share every triangle.
public struct CurvedFaceGeometry: Sendable {
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let textureCoordinates: [SIMD2<Float>]
    public let indices: [UInt32]

    public init(segments: Int = 32) {
        precondition(segments >= 2)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var textureCoordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for row in 0...segments {
            for column in 0...segments {
                let uv = SIMD2(Float(column), Float(row)) / Float(segments)
                let point = FaceLayout.surfacePoint(at: (uv - SIMD2(repeating: 0.5)) * FaceLayout.panelSide)
                positions.append(point)
                normals.append(SoftGlassSurface.normal(at: point))
                textureCoordinates.append(uv)
            }
        }
        for row in 0..<segments {
            for column in 0..<segments {
                let a = UInt32(row * (segments + 1) + column)
                let b = a + 1
                let c = a + UInt32(segments + 1)
                let d = c + 1
                indices.append(contentsOf: [a, b, d, a, d, c])
            }
        }
        self.positions = positions
        self.normals = normals
        self.textureCoordinates = textureCoordinates
        self.indices = indices
    }
}
