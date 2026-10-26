import Foundation

/// Visual light only: never changes the cube's pose or the window geometry.
public struct PrismMotion: Sendable {
    public private(set) var phase = 0.0
    public private(set) var engagement = 0.0

    public init() {}

    public mutating func advance(deltaTime: Double, hovered: Bool, reducedMotion: Bool) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let target = hovered ? 1.0 : 0.0
        guard !reducedMotion else { engagement = target; return }
        // A resumed/occluded window must not flash through a missed animation.
        let delta = min(deltaTime, 0.1)
        phase = (phase + delta / 18).truncatingRemainder(dividingBy: 1)
        engagement += (target - engagement) * (1 - exp(-delta / 0.16))
        if abs(target - engagement) < 0.001 { engagement = target }
    }
}
