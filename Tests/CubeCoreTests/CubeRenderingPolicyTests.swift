import Testing
@testable import CubeCore

struct CubeRenderingPolicyTests {
    @Test func hiddenAndOccludedViewsDoNotAnimate() {
        #expect(CubeRenderingPolicy.mode(visible: false, hovered: true, interacting: true, autoRotates: true, slimeActive: true, reducedMotion: false) == .suspended)
    }
    @Test func idleRotationUsesLowerCadenceAndInteractionRestoresResponsiveness() {
        #expect(CubeRenderingPolicy.mode(visible: true, hovered: false, interacting: false, autoRotates: true, slimeActive: false, reducedMotion: false) == .idle)
        #expect(CubeRenderingPolicy.mode(visible: true, hovered: true, interacting: false, autoRotates: true, slimeActive: false, reducedMotion: false) == .interactive)
        #expect(CubeRenderingPolicy.mode(visible: true, hovered: false, interacting: false, autoRotates: false, slimeActive: true, reducedMotion: false) == .interactive)
    }
    @Test func staticAndReducedMotionCanSuspendButDraggingRemainsResponsive() {
        #expect(CubeRenderingPolicy.mode(visible: true, hovered: false, interacting: false, autoRotates: false, slimeActive: false, reducedMotion: false) == .suspended)
        #expect(CubeRenderingPolicy.mode(visible: true, hovered: false, interacting: false, autoRotates: true, slimeActive: false, reducedMotion: true) == .suspended)
        #expect(CubeRenderingPolicy.mode(visible: true, hovered: false, interacting: true, autoRotates: false, slimeActive: false, reducedMotion: true) == .interactive)
    }
}
