import simd

/// Picks the curved surface. Icon hits interpolate the same UVs used by the renderer.
public enum CubeFacePicking {
    private static let body = SoftGlassGeometry()
    private static let decal = CurvedFaceGeometry()

    public static func icon(origin: SIMD3<Float>, direction: SIMD3<Float>) -> (face: CubeFace, slot: Int)? {
        guard intersectsBounds(origin: origin, direction: direction) else { return nil }
        var nearest: (face: CubeFace, distance: Float, uv: SIMD2<Float>)?
        for face in CubeFace.allCases {
            let localOrigin = face.orientation.inverse.act(origin)
            let localDirection = face.orientation.inverse.act(direction)
            guard let hit = intersection(origin: localOrigin, direction: localDirection,
                                         positions: decal.positions, indices: decal.indices,
                                         textureCoordinates: decal.textureCoordinates, cullBackFaces: true),
                  hit.distance < (nearest?.distance ?? .infinity) else { continue }
            nearest = (face, hit.distance, hit.uv)
        }
        guard let nearest else { return nil }
        let local = (nearest.uv - SIMD2(repeating: 0.5)) * FaceLayout.panelSide
        guard let slot = FaceLayout.iconSlot(at: local) else { return nil }
        return (nearest.face, slot)
    }

    public static func face(origin: SIMD3<Float>, direction: SIMD3<Float>) -> CubeFace? {
        guard intersectsBounds(origin: origin, direction: direction),
              let hit = intersection(origin: origin, direction: direction, positions: body.positions,
                                     indices: body.indices, textureCoordinates: body.textureCoordinates,
                                     cullBackFaces: false) else { return nil }
        let point = origin + hit.distance * direction
        let absolute = simd_abs(point)
        let axis = absolute.x >= absolute.y && absolute.x >= absolute.z ? 0 : absolute.y >= absolute.z ? 1 : 2
        return point[axis] >= 0 ? [.right, .top, .front][axis] : [.left, .bottom, .back][axis]
    }

    private static func intersectsBounds(origin: SIMD3<Float>, direction: SIMD3<Float>) -> Bool {
        guard (0..<3).allSatisfy({ origin[$0].isFinite && direction[$0].isFinite }),
              simd_length_squared(direction) > 0 else { return false }
        var entry = -Float.infinity
        var exit = Float.infinity
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-7 {
                guard abs(origin[axis]) <= 0.502 else { return false }
                continue
            }
            let a = (-0.502 - origin[axis]) / direction[axis]
            let b = (0.502 - origin[axis]) / direction[axis]
            entry = max(entry, min(a, b))
            exit = min(exit, max(a, b))
            guard entry <= exit else { return false }
        }
        return exit >= 0
    }

    private static func intersection(origin: SIMD3<Float>, direction: SIMD3<Float>, positions: [SIMD3<Float>],
                                     indices: [UInt32], textureCoordinates: [SIMD2<Float>],
                                     cullBackFaces: Bool) -> (distance: Float, uv: SIMD2<Float>)? {
        var nearest: (distance: Float, uv: SIMD2<Float>)?
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[offset]), b = Int(indices[offset + 1]), c = Int(indices[offset + 2])
            let firstEdge = positions[b] - positions[a]
            let secondEdge = positions[c] - positions[a]
            let perpendicular = simd_cross(direction, secondEdge)
            let determinant = simd_dot(firstEdge, perpendicular)
            guard cullBackFaces ? determinant > 1e-9 : abs(determinant) > 1e-9 else { continue }
            let fromVertex = origin - positions[a]
            let u = simd_dot(fromVertex, perpendicular) / determinant
            guard u >= -0.000001 && u <= 1.000001 else { continue }
            let cross = simd_cross(fromVertex, firstEdge)
            let v = simd_dot(direction, cross) / determinant
            guard v >= -0.000001 && u + v <= 1.000001 else { continue }
            let distance = simd_dot(secondEdge, cross) / determinant
            guard distance >= 0 && distance < (nearest?.distance ?? .infinity) else { continue }
            let uv = textureCoordinates[a] * (1 - u - v) + textureCoordinates[b] * u + textureCoordinates[c] * v
            nearest = (distance, uv)
        }
        return nearest
    }
}
