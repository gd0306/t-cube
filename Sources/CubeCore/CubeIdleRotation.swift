import Foundation
import simd

/// Slow angular drift with independently seeded directions and smooth transitions.
/// Only active time advances the path, so hovering never builds up a catch-up turn.
public struct CubeIdleRotation: Sendable {
    private var random: Generator
    private var fromVelocity: SIMD3<Float>
    private var toVelocity: SIMD3<Float>
    private var elapsed = 0.0
    private var duration: Double

    public init(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        var random = Generator(state: seed)
        fromVelocity = Self.velocity(using: &random)
        toVelocity = Self.velocity(using: &random)
        duration = Double.random(in: 5...9, using: &random)
        self.random = random
    }

    public mutating func advance(from orientation: simd_quatf, deltaTime: Double, paused: Bool) -> simd_quatf {
        guard !paused, deltaTime.isFinite, deltaTime > 0 else { return orientation }
        let delta = min(deltaTime, 0.1)
        elapsed += delta
        if elapsed >= duration {
            elapsed -= duration
            fromVelocity = toVelocity
            toVelocity = Self.velocity(using: &random)
            duration = Double.random(in: 5...9, using: &random)
        }
        let t = Float(elapsed / duration)
        let blend = t * t * (3 - 2 * t)
        let velocity = fromVelocity + (toVelocity - fromVelocity) * blend
        let speed = simd_length(velocity)
        guard speed > 0.000001 else { return orientation }
        let step = simd_quatf(angle: speed * Float(delta), axis: velocity / speed)
        return simd_normalize(step * orientation)
    }

    private static func velocity(using random: inout Generator) -> SIMD3<Float> {
        // Sample a sphere rather than favoring one axis or a fixed rotation loop.
        let z = Float.random(in: -1...1, using: &random)
        let azimuth = Float.random(in: 0..<(2 * .pi), using: &random)
        let radius = sqrt(max(0, 1 - z * z))
        let speed = Float.random(in: 0.09...0.18, using: &random)
        return SIMD3(radius * cos(azimuth), radius * sin(azimuth), z) * speed
    }

    private struct Generator: RandomNumberGenerator, Sendable {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
    }
}
