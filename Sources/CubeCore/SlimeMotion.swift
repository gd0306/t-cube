import Foundation
import simd

/// A continuous local pull. The optical shell deforms; launcher decals stay still.
public struct SlimeDeformation: Equatable, Sendable {
    public var contact = SIMD3<Float>(0, 0, 0.5)
    public var pull: Float = 0
    public var shear = SIMD3<Float>.zero

    public init() {}

    private var displacement: SIMD3<Float> {
        let normal = simd_normalize(contact * contact * contact)
        return normal * pull + shear
    }

    public func position(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let weight = exp(-9 * simd_length_squared(point - contact))
        return point * (1 - 0.06 * pull) + displacement * weight
    }

    public func normal(_ normal: SIMD3<Float>, at point: SIMD3<Float>) -> SIMD3<Float> {
        let difference = point - contact
        let gradient = -18 * difference * exp(-9 * simd_length_squared(difference))
        let scale = 1 - 0.06 * pull
        // Inverse transpose of the deformation Jacobian keeps highlights attached
        // to the bent surface instead of lighting the undeformed mesh.
        let denominator = scale + simd_dot(gradient, displacement)
        return simd_normalize(normal - gradient * simd_dot(displacement, normal) / max(0.2, denominator))
    }
}

public struct SlimeMotion: Sendable {
    public private(set) var deformation = SlimeDeformation()
    private var target: SIMD3<Float>?
    private var velocity: Float = 0

    public init() {}

    public var isActive: Bool {
        target != nil || abs(deformation.pull) > 0.00001 || abs(velocity) > 0.0001 || simd_length(deformation.shear) > 0.00001
    }

    public mutating func setContact(_ point: SIMD3<Float>?) {
        guard let point, (0..<3).allSatisfy({ point[$0].isFinite }), simd_length_squared(point) > 0.01 else {
            target = nil
            return
        }
        let bounded = simd_clamp(point, SIMD3(repeating: -0.7), SIMD3(repeating: 0.7))
        if !isActive { deformation.contact = bounded }
        target = bounded
    }

    public mutating func advance(deltaTime: Double, reducedMotion: Bool) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        if reducedMotion {
            deformation.pull = 0
            deformation.shear = .zero
            velocity = 0
            target = nil
            return
        }
        var remaining = Float(min(deltaTime, 0.05))
        while remaining > 0 {
            let step = min(remaining, 1.0 / 120)
            let targetPull: Float = target == nil ? 0 : 0.13
            velocity += ((targetPull - deformation.pull) * 260 - velocity * 12) * step
            deformation.pull += velocity * step
            if let target {
                let lag = target - deformation.contact
                deformation.contact += lag * (1 - exp(-step / 0.075))
                var shear = lag * 0.4
                let length = simd_length(shear)
                if length > 0.09 { shear *= 0.09 / length }
                deformation.shear += (shear - deformation.shear) * (1 - exp(-step / 0.045))
            } else {
                deformation.shear *= exp(-step / 0.12)
            }
            remaining -= step
        }
        if target == nil, abs(deformation.pull) < 0.00001, abs(velocity) < 0.0001,
           simd_length(deformation.shear) < 0.00001 {
            deformation.pull = 0
            deformation.shear = .zero
            velocity = 0
        }
    }
}
