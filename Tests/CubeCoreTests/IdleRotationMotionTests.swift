import Testing
import simd
@testable import CubeCore

struct IdleRotationMotionTests {
    @Test func wanderingMotionChangesItsAxisSmoothlyAndKeepsAUnitQuaternion() {
        var motion = CubeIdleRotation(seed: 42)
        var pose = simd_quatf(angle: 0, axis: [0, 1, 0])
        var firstAxis: SIMD3<Float>?
        var changedAxis = false
        var previousStep: SIMD3<Float>?
        for index in 0..<2400 {
            let next = motion.advance(from: pose, deltaTime: 1.0 / 30, paused: false)
            let step = next * pose.inverse
            let angle = 2 * atan2(simd_length(step.imag), abs(step.real))
            #expect(angle <= 0.008, "Idle movement must stay slow")
            #expect(abs(simd_length(next.vector) - 1) < 0.00001)
            let axis = simd_normalize(step.imag)
            if index == 0 { firstAxis = axis }
            if let firstAxis, simd_length(axis - firstAxis) > 0.4 { changedAxis = true }
            if let previousStep { #expect(simd_length(step.imag - previousStep) < 0.0001, "Direction changes must blend instead of snapping") }
            previousStep = step.imag
            pose = next
        }
        #expect(changedAxis)
        #expect(simd_length(pose.imag) > 0.01)
    }

    @Test func pausingDoesNotAccumulateMotionOrResetAManuallyChosenPose() {
        var motion = CubeIdleRotation(seed: 7)
        var uninterrupted = motion
        let manuallyChosen = simd_quatf(angle: 0.73, axis: simd_normalize(SIMD3<Float>(1, 2, 3)))
        for _ in 0..<300 {
            let frozen = motion.advance(from: manuallyChosen, deltaTime: 1, paused: true)
            #expect(frozen.vector == manuallyChosen.vector)
        }
        let resumed = motion.advance(from: manuallyChosen, deltaTime: 0.03, paused: false)
        let expected = uninterrupted.advance(from: manuallyChosen, deltaTime: 0.03, paused: false)
        #expect(simd_length(resumed.vector - expected.vector) < 0.00001)
        #expect(simd_length(resumed.vector - manuallyChosen.vector) > 0.0001)
        #expect(simd_length(resumed.vector - manuallyChosen.vector) < 0.01)
    }

    @Test func invalidFramesAreIgnoredAndLongFramesCannotCauseALargeJump() {
        var motion = CubeIdleRotation(seed: 123)
        var limited = motion
        let pose = simd_quatf(angle: 0, axis: [0, 1, 0])
        for delta in [Double.nan, .infinity, -1, 0] {
            #expect(motion.advance(from: pose, deltaTime: delta, paused: false).vector == pose.vector)
        }
        let resumed = motion.advance(from: pose, deltaTime: 600, paused: false)
        let capped = limited.advance(from: pose, deltaTime: 0.1, paused: false)
        #expect(simd_length(resumed.vector - capped.vector) < 0.00001)
        #expect(simd_length(resumed.imag) < 0.02)
    }
}
