import simd

/// Picks the full cube surface, including clear areas outside the icon texture.
public enum CubeFacePicking {
    public static func face(origin: SIMD3<Float>, direction: SIMD3<Float>) -> CubeFace? {
        guard (0..<3).allSatisfy({ origin[$0].isFinite && direction[$0].isFinite }),
              simd_length_squared(direction) > 0 else { return nil }
        let negative: [CubeFace] = [.left, .bottom, .back]
        let positive: [CubeFace] = [.right, .top, .front]
        var entry = -Float.infinity
        var exit = Float.infinity
        var entryFace: CubeFace?
        var exitFace: CubeFace?
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-7 {
                guard abs(origin[axis]) <= 0.5 else { return nil }
                continue
            }
            let a = (-0.5 - origin[axis]) / direction[axis]
            let b = (0.5 - origin[axis]) / direction[axis]
            let near = min(a, b)
            let far = max(a, b)
            if near > entry {
                entry = near
                entryFace = a < b ? negative[axis] : positive[axis]
            }
            if far < exit {
                exit = far
                exitFace = a < b ? positive[axis] : negative[axis]
            }
            guard entry <= exit else { return nil }
        }
        guard exit >= 0 else { return nil }
        return entry >= 0 ? entryFace : exitFace
    }
}
