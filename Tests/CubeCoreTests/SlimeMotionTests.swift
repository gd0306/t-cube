import Testing
import simd
@testable import CubeCore

struct SlimeMotionTests {
    @Test func contactPullsNearbySurfaceAndReleaseSettlesBackToRest() {
        var motion = SlimeMotion()
        let near = SIMD3<Float>(0, 0, 0.5)
        let far = SIMD3<Float>(0, 0, -0.5)
        motion.setContact(near)
        for _ in 0..<30 { motion.advance(deltaTime: 1.0 / 60, reducedMotion: false) }
        #expect(motion.deformation.position(near).z > 0.56)
        #expect(simd_distance(motion.deformation.position(far), far) < 0.03)
        motion.setContact(nil)
        var crossedRest = false
        for _ in 0..<240 {
            motion.advance(deltaTime: 1.0 / 60, reducedMotion: false)
            crossedRest = crossedRest || motion.deformation.pull < 0
        }
        #expect(crossedRest, "A soft release should have a small elastic overshoot")
        #expect(simd_distance(motion.deformation.position(near), near) < 0.0001)
        #expect(!motion.isActive)
    }

    @Test func movingContactCreatesLagAndSettlesAtTheNewSurfacePoint() {
        var motion = SlimeMotion()
        motion.setContact([-0.4, 0, 0.45])
        for _ in 0..<40 { motion.advance(deltaTime: 1.0 / 60, reducedMotion: false) }
        motion.setContact([0.4, 0, 0.45])
        motion.advance(deltaTime: 1.0 / 60, reducedMotion: false)
        #expect(simd_length(motion.deformation.shear) > 0.01)
        #expect(motion.deformation.contact.x < 0.3, "The jelly should trail a fast pointer")
        for _ in 0..<90 { motion.advance(deltaTime: 1.0 / 60, reducedMotion: false) }
        let point = SIMD3<Float>(0.4, 0, 0.45)
        #expect(motion.deformation.position(point).x > point.x)
        #expect(simd_length(motion.deformation.shear) < 0.001)
    }

    @Test func reducedMotionAndInvalidTimeCannotLeaveAnAnimatedDeformation() {
        var motion = SlimeMotion()
        motion.setContact([0, 0, 0.5])
        motion.advance(deltaTime: 0.05, reducedMotion: false)
        let previous = motion.deformation
        for time in [Double.nan, .infinity, -1, 0] {
            motion.advance(deltaTime: time, reducedMotion: false)
            #expect(motion.deformation == previous)
        }
        motion.advance(deltaTime: 600, reducedMotion: false)
        #expect(abs(motion.deformation.pull) < 0.18)
        motion.advance(deltaTime: 0.05, reducedMotion: true)
        #expect(motion.deformation.position([0, 0, 0.5]) == SIMD3<Float>(0, 0, 0.5))
        #expect(!motion.isActive)
    }
}
