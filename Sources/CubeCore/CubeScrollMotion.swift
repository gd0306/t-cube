import simd

/// Screen-relative rotation: the front surface follows the user's fingers on both axes.
public enum CubeScrollMotion {
    public static func rotated(from presented: simd_quatf, delta: SIMD2<Float>, precise: Bool, inverted: Bool) -> simd_quatf {
        guard delta.x.isFinite, delta.y.isFinite else { return presented }
        // AppKit inverts scroll deltas for Natural Scrolling. Undo that device
        // preference, then map device-left-positive X into screen-right-positive X.
        let device = inverted ? -delta : delta
        var movement = SIMD2<Float>(-device.x, device.y)
        if precise {
            movement.x = max(-100, min(100, movement.x))
            movement.y = max(-100, min(100, movement.y))
        } else {
            movement = SIMD2<Float>(movement.x == 0 ? 0 : (movement.x > 0 ? 1 : -1), movement.y == 0 ? 0 : (movement.y > 0 ? 1 : -1))
        }
        let logical = CubeRotation.displayTilt.inverse * presented
        let rotated = CubeRotation.dragged(from: logical, translation: movement, radiansPerPoint: precise ? 0.022 : .pi / 2)
        return simd_normalize(CubeRotation.displayTilt * rotated)
    }

    public static func targetFace(for presented: simd_quatf) -> CubeFace {
        CubeRotation.nearestFace(to: CubeRotation.displayTilt.inverse * presented)
    }
}
