import Testing
@testable import CubeCore

struct PrismMotionTests {
    @Test func hoverLightEasesAndReversesWithoutOvershooting() {
        var motion = PrismMotion()
        motion.advance(deltaTime: 0.05, hovered: true, reducedMotion: false)
        let rising = motion.engagement
        #expect(rising > 0 && rising < 1)
        motion.advance(deltaTime: 0.05, hovered: false, reducedMotion: false)
        #expect(motion.engagement > 0 && motion.engagement < rising)
        for _ in 0..<200 { motion.advance(deltaTime: 0.05, hovered: true, reducedMotion: false) }
        #expect(motion.engagement > 0.999 && motion.engagement <= 1)
        #expect(motion.phase >= 0 && motion.phase < 1)
    }

    @Test func reducedMotionFreezesFlowButStillRespondsToHover() {
        var motion = PrismMotion()
        motion.advance(deltaTime: 0.1, hovered: false, reducedMotion: false)
        let phase = motion.phase
        for _ in 0..<30 { motion.advance(deltaTime: 0.1, hovered: true, reducedMotion: true) }
        #expect(motion.phase == phase)
        #expect(motion.engagement == 1)
        motion.advance(deltaTime: 0.1, hovered: false, reducedMotion: true)
        #expect(motion.engagement == 0)
    }

    @Test func invalidAndSuspendedFrameTimesCannotJumpTheLight() {
        var motion = PrismMotion()
        for delta in [Double.nan, .infinity, -1, 0] {
            motion.advance(deltaTime: delta, hovered: true, reducedMotion: false)
        }
        #expect(motion.phase == 0 && motion.engagement == 0)
        motion.advance(deltaTime: 60, hovered: true, reducedMotion: false)
        #expect(motion.phase > 0 && motion.phase < 0.01)
        #expect(motion.engagement > 0 && motion.engagement < 0.6)
    }
}
